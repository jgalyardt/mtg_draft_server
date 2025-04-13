defmodule MtgDraftServer.Drafts.PackGenerator do
  @moduledoc """
  Generates booster packs for a draft based on the modern draft booster distribution.

  A modern draft booster (ignoring the marketing token) contains 15 Magic cards:
    - 1 Basic Land
    - 10 Common Cards
    - 3 Uncommon Cards
    - 1 Rare or Mythic Rare Card

  Additionally, there is a chance for one of the common cards to be replaced by a premium foil card
  (of any rarity). In that case the pack will have:
    - 1 Basic Land
    - 1 Foil Card
    - 9 Common Cards
    - 3 Uncommon Cards
    - 1 Rare or Mythic Rare Card

  Accepted options (opts):
    - :set_codes - a list of set codes (e.g. ["ulg", "m21"])
    - :allowed_rarities - a list of rarities to include (default: ["basic", "common", "uncommon", "rare", "mythic"])
    - :allowed_layouts - a list of card layouts to include (default: normal, split, flip, etc.)
    - :distribution - a map defining the default booster composition.
      Defaults to `%{"basic" => 1, "common" => 10, "uncommon" => 3, "rare" => 1}`.

  Additionally, packs can be distributed among players. For example, if a draft has 8 players,
  24 booster packs (8 × 3) will be generated and then grouped into three packs per player.
  """

  alias MtgDraftServer.Repo
  alias MtgDraftServer.Cards.Card
  import Ecto.Query

  @default_distribution %{"basic" => 1, "common" => 10, "uncommon" => 3, "rare" => 1}
  @foil_chance 0.25

  # Add default layouts for drafting
  @default_draft_layouts [
    "normal",
    "split",
    "flip",
    "transform",
    "modal_dfc",
    "adventure",
    "leveler",
    "saga",
    "class"
  ]

  @doc """
  Parses options and provides default values for missing options.

  Returns a map with parsed options including:
    - :set_codes - list of set codes to filter cards
    - :allowed_rarities - list of allowed card rarities
    - :allowed_layouts - list of allowed card layouts
    - :distribution - map defining the booster pack composition
  """
  def parse_opts(opts) do
    %{
      set_codes: Map.get(opts, :set_codes, []),
      allowed_rarities:
        Map.get(opts, :allowed_rarities, ["basic", "common", "uncommon", "rare", "mythic"]),
      allowed_layouts: Map.get(opts, :allowed_layouts, @default_draft_layouts),
      distribution: Map.get(opts, :distribution, @default_distribution)
    }
  end

  @doc """
  Fetches cards from the database based on the provided options.

  This function queries cards matching the provided set codes, allowed rarities,
  and allowed layouts.

  Returns a list of Card structs.
  """
  def fetch_card_pool(%{
        set_codes: set_codes,
        allowed_rarities: allowed_rarities,
        allowed_layouts: allowed_layouts
      }) do
    base_query =
      from card in Card,
        where: card.rarity in ^allowed_rarities

    # Join with a subquery that fetches layout information
    layout_query =
      from card in base_query,
        inner_join: metadata in "card_metadata",
        on: card.id == metadata.card_id,
        where: metadata.layout in ^allowed_layouts

    query =
      if set_codes == [] do
        layout_query
      else
        from card in layout_query, where: card.set_code in ^set_codes
      end

    Repo.all(query)
  end

  @doc """
  Generates a single booster pack using the given rarity groups and distribution.

  The process is as follows:
    1. Pick the required number of basic lands, commons, and uncommons.
    2. For the rare slot, combine the "rare" and "mythic" groups and pick one card.
    3. With a chance of #{@foil_chance * 100}%, select a foil card from all foil-eligible cards,
       remove one common card, and insert the foil.
    4. Shuffle the pack before returning it.

  Returns a list of cards representing the booster pack.
  """
  def generate_single_pack(rarity_groups, distribution) do
    basics = Enum.take_random(Map.get(rarity_groups, "basic", []), distribution["basic"])
    commons = Enum.take_random(Map.get(rarity_groups, "common", []), distribution["common"])
    uncommons = Enum.take_random(Map.get(rarity_groups, "uncommon", []), distribution["uncommon"])
    rare_pool = Map.get(rarity_groups, "rare", []) ++ Map.get(rarity_groups, "mythic", [])
    rare = Enum.take_random(rare_pool, distribution["rare"])

    initial_pack = basics ++ commons ++ uncommons ++ rare

    pack =
      if :rand.uniform() <= @foil_chance do
        case pick_foil_card(rarity_groups) do
          nil ->
            initial_pack

          foil_card ->
            if length(commons) > 0 do
              index = :rand.uniform(length(commons)) - 1
              new_commons = List.delete_at(commons, index)
              basics ++ new_commons ++ uncommons ++ rare ++ [foil_card]
            else
              initial_pack ++ [foil_card]
            end
        end
      else
        initial_pack
      end

    Enum.shuffle(pack)
  end

  @doc """
  Generates the specified number of booster packs using the provided rarity groups and distribution.

  By default, generates 24 packs (suitable for 8 players receiving 3 packs each).

  Returns a list of lists, where each inner list represents a booster pack of cards.
  """
  def generate_all_packs(rarity_groups, distribution, num_packs \\ 24) do
    Enum.map(1..num_packs, fn _ -> generate_single_pack(rarity_groups, distribution) end)
  end

  @doc """
  Generates booster packs based on the provided options.

  This function:
    1. Parses the provided options
    2. Fetches cards from the database
    3. Groups the cards by rarity

  Returns a map with:
    - :opts - parsed options
    - :rarity_groups - a map grouping cards by rarity
  """
  def generate_booster_packs(opts \\ %{}) do
    parsed_opts = parse_opts(opts)
    cards = fetch_card_pool(parsed_opts)
    rarity_groups = group_cards_by_rarity(cards)

    %{opts: parsed_opts, rarity_groups: rarity_groups}
  end

  @doc """
  Generates packs from multiple different sets for a draft.

  This function:
    1. Generates packs for each set in the pack_sets list
    2. Groups and distributes the packs among players

  Parameters:
    - player_count - the number of players in the draft
    - pack_sets - a list of set codes, one for each round of the draft

  Returns a map where keys are player IDs and values are lists of packs, with one pack
  from each set for each player.
  """
  def generate_multi_set_packs(player_count, pack_sets) do
    packs_per_player = length(pack_sets)

    # Ensure the number of packs is a multiple of player_count
    if rem(packs_per_player, player_count) != 0 do
      raise ArgumentError, "Number of packs per player must be a multiple of player_count"
    end

    # Generate packs for each set configuration
    all_packs =
      Enum.flat_map(pack_sets, fn set_code ->
        # Generate player_count packs from this set
        generate_packs_for_set(player_count, set_code)
      end)

    # Group packs by set in order
    grouped_packs = Enum.chunk_every(all_packs, player_count)

    # Distribute to players
    player_ids = Enum.map(1..player_count, &Integer.to_string/1)

    # Structure: %{"player_id" => [[pack1_cards], [pack2_cards], [pack3_cards]]}
    Enum.reduce(player_ids, %{}, fn player_id, acc ->
      player_packs =
        grouped_packs
        |> Enum.map(fn set_packs ->
          # Take one pack from each set for this player
          Enum.at(set_packs, String.to_integer(player_id) - 1)
        end)

      Map.put(acc, player_id, player_packs)
    end)
  end

  @doc """
  Distributes booster packs to players.

  Given a list of players and a list of booster packs, groups the packs so that each player
  receives three packs. It assumes that length(packs) == length(players) * 3.

  Returns a map where keys are player identifiers (or player structs) and values are lists of packs.
  """
  def distribute_packs(packs, players) do
    packs_per_player = 3
    packs_chunks = Enum.chunk_every(packs, packs_per_player)

    Enum.zip(players, packs_chunks)
    |> Enum.into(%{})
  end

  @doc """
  Generates and distributes booster packs to the given players.

  Parameters:
    - opts – options for pack generation (see generate_booster_packs/1)
    - players – a list of player identifiers (or player structs)

  Returns a map of player => list of booster packs, where each player gets three packs.
  """
  def generate_and_distribute_booster_packs(opts \\ %{}, players) do
    %{opts: parsed_opts, rarity_groups: rarity_groups} = generate_booster_packs(opts)
    total_packs = length(players) * 3
    packs = generate_all_packs(rarity_groups, parsed_opts.distribution, total_packs)
    distribute_packs(packs, players)
  end

  # --- Private Helpers ---

  defp generate_packs_for_set(count, set_code) do
    %{opts: parsed_opts, rarity_groups: rarity_groups} =
      generate_booster_packs(%{set_codes: [set_code]})

    generate_all_packs(rarity_groups, parsed_opts.distribution, count)
  end

  defp group_cards_by_rarity(cards) do
    Enum.group_by(cards, & &1.rarity)
  end

  defp pick_foil_card(rarity_groups) do
    all_cards = Enum.flat_map(rarity_groups, fn {_rarity, cards} -> cards end)
    foil_pool = Enum.filter(all_cards, fn card -> card.foil end)

    case foil_pool do
      [] -> nil
      _ -> Enum.random(foil_pool)
    end
  end
end

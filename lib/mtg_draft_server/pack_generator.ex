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

  @doc """
  Prepares the booster pack card pool based on the provided options.

  This function:
    1. Parses the incoming options and fills in defaults.
    2. Queries the database for cards matching the provided set codes and allowed rarities.
    3. Groups the resulting cards by rarity.

  Returns a map with:
    - :opts - the parsed options
    - :rarity_groups - a map of rarity to a list of matching cards
  """
  def generate_booster_packs(opts \\ %{}) do
    parsed_opts = parse_opts(opts)
    cards = fetch_card_pool(parsed_opts)
    rarity_groups = group_cards_by_rarity(cards)
    %{opts: parsed_opts, rarity_groups: rarity_groups}
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
  """
  def generate_all_packs(rarity_groups, distribution, num_packs \\ 24) do
    Enum.map(1..num_packs, fn _ -> generate_single_pack(rarity_groups, distribution) end)
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

  * opts – options for pack generation (see generate_booster_packs/1)
  * players – a list of player identifiers (or player structs)

  Returns a map of player => list of booster packs.
  """
  def generate_and_distribute_booster_packs(opts \\ %{}, players) do
    %{opts: parsed_opts, rarity_groups: rarity_groups} = generate_booster_packs(opts)
    total_packs = length(players) * 3
    packs = generate_all_packs(rarity_groups, parsed_opts.distribution, total_packs)
    distribute_packs(packs, players)
  end

  # --- Private Helpers ---

  defp parse_opts(opts) do
    %{
      set_codes: Map.get(opts, :set_codes, []),
      allowed_rarities:
        Map.get(opts, :allowed_rarities, ["basic", "common", "uncommon", "rare", "mythic"]),
      distribution: Map.get(opts, :distribution, @default_distribution)
    }
  end

  defp fetch_card_pool(%{set_codes: set_codes, allowed_rarities: allowed_rarities}) do
    base_query =
      from card in Card,
        where: card.rarity in ^allowed_rarities

    query =
      if set_codes == [] do
        base_query
      else
        from card in base_query, where: card.set_code in ^set_codes
      end

    Repo.all(query)
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

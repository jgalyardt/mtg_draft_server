# lib/mtg_draft_server/draft_session/pack_distributor.ex
defmodule MtgDraftServer.DraftSession.PackDistributor do
  @moduledoc """
  Handles the distribution and manipulation of card packs during a draft session.

  This module provides utility functions for:
  - Removing cards from packs
  - Checking if a card exists in a pack
  - Determining the next player to receive a pack based on draft direction
  """

  @doc "Remove a card_id from a pack (list of card structs or IDs)."
  def remove_card(pack, card_id) do
    Enum.reject(pack, fn
      %{id: ^card_id} -> true
      ^card_id -> true
      _ -> false
    end)
  end

  @doc "True if card_id exists in pack."
  def card_in_pack?(pack, card_id) do
    Enum.any?(pack, fn
      %{id: ^card_id} -> true
      ^card_id -> true
      _ -> false
    end)
  end

  @doc """
  Given the full list of players (in seating order) and a direction,
  return the neighbor to the :left or :right (wrap around).
  """
  def next_neighbor(user_id, players, direction) do
    n = length(players)
    idx = Enum.find_index(players, &(&1 == user_id))

    next_idx =
      case direction do
        :right -> rem(idx + 1, n)
        :left -> rem(idx - 1 + n, n)
      end

    Enum.at(players, next_idx)
  end
end

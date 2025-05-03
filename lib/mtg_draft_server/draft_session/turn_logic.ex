defmodule MtgDraftServer.DraftSession.TurnLogic do
  @moduledoc """
  Provides utility functions for managing turn order and player rotation in a draft.
  
  This module handles the logic for determining the next player in a draft rotation,
  taking into account the direction of the draft (left or right) and ensuring proper
  wrapping around the table.
  """
  
  @doc """
  Calculates the index of the next player in the draft rotation.
  
  ## Parameters
    - current_index: The index of the current player
    - player_count: The total number of players in the draft
    - direction: The direction of the draft rotation (:left or :right)
    
  ## Returns
    The index of the next player, wrapping around if necessary
  """
  @spec next_index(integer(), integer(), :left | :right) :: integer()
  def next_index(current_index, player_count, :left), do: rem(current_index + 1, player_count)

  @doc """
  Calculates the index of the next player when passing to the right.
  
  This is equivalent to moving to the previous player in the array, with wrapping.
  
  ## Parameters
    - current_index: The index of the current player
    - player_count: The total number of players in the draft
    - :right: Indicates passing to the right
    
  ## Returns
    The index of the next player, wrapping around if necessary
  """
  def next_index(current_index, player_count, :right),
    do: rem(player_count + current_index - 1, player_count)
end

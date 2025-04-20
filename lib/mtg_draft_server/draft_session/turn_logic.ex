defmodule MtgDraftServer.DraftSession.TurnLogic do
  @spec next_index(integer(), integer(), :left | :right) :: integer()
  def next_index(current_index, player_count, :left), do: rem(current_index + 1, player_count)

  def next_index(current_index, player_count, :right),
    do: rem(player_count + current_index - 1, player_count)
end

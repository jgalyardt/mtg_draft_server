defmodule MtgDraftServerWeb.DraftChannel do
    use Phoenix.Channel
    alias Phoenix.PubSub
  
    @pubsub MtgDraftServer.PubSub
  
    @doc """
    When a client does `socket.channel("draft:{draft_id}", _)`,
    we subscribe them to the same PubSub topic so broadcasts flow through.
    """
    def join("draft:" <> draft_id, _params, socket) do
      :ok = PubSub.subscribe(@pubsub, "draft:#{draft_id}")
      {:ok, assign(socket, :draft_id, draft_id)}
    end
  
    # Forward the draft_completed broadcast into a channel push
    def handle_info({:draft_completed, draft_id}, socket) do
      push(socket, "draft_completed", %{draft_id: draft_id})
      {:noreply, socket}
    end
  
    # You can handle other PubSub events the same way:
    # def handle_info({:pack_updated, user, neighbor}, socket) do
    #   push(socket, "pack_updated", %{user: user, neighbor: neighbor})
    #   {:noreply, socket}
    # end
  end
  
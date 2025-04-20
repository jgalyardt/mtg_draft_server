defmodule MtgDraftServerWeb.DashboardLive do
  use MtgDraftServerWeb, :live_view

  alias MtgDraftServer.Drafts

  @impl true
  def mount(_params, _session, socket) do
    drafts = Drafts.list_active_drafts_with_players()

    socket =
      socket
      |> assign(:page_title, "Admin Dashboard")
      |> assign(:drafts, drafts)
      |> assign(:expanded_drafts, %{})
      |> assign(:expanded_players, %{})
      |> assign(:player_picks, %{})

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_draft", %{"draft_id" => draft_id}, socket) do
    expanded =
      socket.assigns.expanded_drafts
      |> Map.update(draft_id, true, &(!&1))

    {:noreply, assign(socket, :expanded_drafts, expanded)}
  end

  @impl true
  def handle_event("toggle_player", %{"draft_id" => draft_id, "user_id" => user_id}, socket) do
    key = {draft_id, user_id}

    expanded_players =
      socket.assigns.expanded_players
      |> Map.update(key, true, &(!&1))

    player_picks =
      if expanded_players[key] do
        picks = Drafts.get_picked_cards(draft_id, user_id)
        Map.put(socket.assigns.player_picks, key, picks)
      else
        Map.delete(socket.assigns.player_picks, key)
      end

    {:noreply,
     socket
     |> assign(:expanded_players, expanded_players)
     |> assign(:player_picks, player_picks)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-4">
      <h1 class="text-2xl font-bold mb-4">Active Drafts</h1>
      <ul class="space-y-2">
        <%= for draft <- @drafts do %>
          <li class="border rounded p-2">
            <button
              class="font-mono"
              phx-click="toggle_draft"
              phx-value-draft_id={draft.id}
            >
              <%= if @expanded_drafts[draft.id], do: "▾", else: "▸" %>
              Draft <%= draft.id %>
            </button>

            <%= if @expanded_drafts[draft.id] do %>
              <ul class="ml-6 mt-2 space-y-1">
                <%= for player <- draft.players do %>
                  <li>
                    <button
                      class="font-mono"
                      phx-click="toggle_player"
                      phx-value-draft_id={draft.id}
                      phx-value-user_id={player.user_id}
                    >
                      <%= if @expanded_players[{draft.id, player.user_id}], do: "▾", else: "▸" %>
                      Player <%= player.user_id %>
                    </button>

                    <%= if @expanded_players[{draft.id, player.user_id}] do %>
                      <ul class="ml-6 mt-1 list-disc list-inside">
                        <%= for pick <- @player_picks[{draft.id, player.user_id}] || [] do %>
                          <li>
                            Pick <%= pick.pick_number %>: <%= pick.card.name %>
                          </li>
                        <% end %>
                      </ul>
                    <% end %>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end
end

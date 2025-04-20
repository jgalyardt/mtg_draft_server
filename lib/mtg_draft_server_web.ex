defmodule MtgDraftServerWeb do
  @moduledoc """
  The entrypoint for defining your web interface:
    use MtgDraftServerWeb, :controller
    use MtgDraftServerWeb, :live_view
    use MtgDraftServerWeb, :html
  """

  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html, :json],
        layouts: [html: MtgDraftServerWeb.Layouts]

      import Plug.Conn
      import MtgDraftServerWeb.Gettext
      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {MtgDraftServerWeb.Layouts, :app}

      # No more Phoenix.View import
      import Phoenix.Component
      import Phoenix.HTML
      import Phoenix.LiveView.Helpers

      import MtgDraftServerWeb.ErrorHelpers
      import MtgDraftServerWeb.Gettext

      unquote(verified_routes())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      import Phoenix.HTML
      import MtgDraftServerWeb.Gettext

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: MtgDraftServerWeb.Endpoint,
        router: MtgDraftServerWeb.Router,
        statics: MtgDraftServerWeb.static_paths()
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end

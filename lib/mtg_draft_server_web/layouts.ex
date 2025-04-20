defmodule MtgDraftServerWeb.Layouts do
  use MtgDraftServerWeb, :html

  # bring in get_csrf_token/0 for your meta tag
  import Phoenix.Controller, only: [get_csrf_token: 0]

  # embed all of your HEEx layouts under components/layouts/
  embed_templates "components/layouts/*"
end

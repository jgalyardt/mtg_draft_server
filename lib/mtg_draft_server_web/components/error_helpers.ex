defmodule MtgDraftServerWeb.ErrorHelpers do
  @moduledoc """
  Function component for rendering form field errors.

  Usage in HEEx:
      <.error_tag form={@form} field={:email} />
  """

  use MtgDraftServerWeb, :html

  # Define component assigns
  attr :form, Phoenix.HTML.Form, required: true
  attr :field, :atom, required: true

  @doc """
  Renders each error for the given field inside a <span> with class "form-error".
  """
  def error_tag(assigns) do
    errors = Keyword.get_values(assigns.form.errors, assigns.field)
    assigns = assign(assigns, :errors, errors)

    ~H"""
    <%= for {msg, opts} <- @errors do %>
      <span class="form-error"><%= translate_error({msg, opts}) %></span>
    <% end %>
    """
  end

  @doc """
  Translates an error tuple or string via Gettext.
  """
  def translate_error({msg, opts}) when is_binary(msg) and is_list(opts) do
    if count = opts[:count] do
      Gettext.dngettext(MtgDraftServerWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(MtgDraftServerWeb.Gettext, "errors", msg, opts)
    end
  end

  def translate_error(msg) when is_binary(msg) do
    Gettext.dgettext(MtgDraftServerWeb.Gettext, "errors", msg)
  end
end

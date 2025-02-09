defmodule MtgDraftServerWeb.FallbackController do
  use MtgDraftServerWeb, :controller

  # For Ecto errors, you might pattern match like this:
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: changeset})
  end

  def call(conn, {:error, message}) when is_binary(message) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: message})
  end
end

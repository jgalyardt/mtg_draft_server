defmodule MtgDraftServerWeb.UserSocket do
    use Phoenix.Socket
  
    ## Channels
    channel "draft:*", MtgDraftServerWeb.DraftChannel
  
    @doc """
    Clients connect with params that include `token`. You can verify it here.
    """
    def connect(%{"token" => _token} = _params, socket, _connect_info) do
      {:ok, socket}
    end
  
    # Reject any socket connection without a token
    def connect(_params, _socket, _connect_info), do: :error
  
    @doc "Socket ids are not used in this app"
    def id(_socket), do: nil
  end
  
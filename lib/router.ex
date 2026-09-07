defmodule Amur.Router do
  @moduledoc """
  Plug router for the Amur OAuth flow.

  Mount it under your router, for example with `forward "/auth", Amur.Router`
  (in Phoenix, inside a browser pipeline and with `alias: false`). It exposes,
  relative to the mount point:

    * `GET /auth/:provider` - start the OAuth flow
    * `GET /auth/:provider/callback` - handle the provider callback
  """

  import Plug.Conn

  @doc """
  Initializes the router with the options supplied by Plug.

  Amur does not currently require router options, so they are returned
  unchanged for Plug's supervision and compilation conventions.
  """
  def init(opts), do: opts

  @doc """
  Fetches request state and dispatches the supported OAuth routes.

  Query parameters and the session are fetched before dispatch so the
  controller can build authorization requests and validate callbacks. Unknown
  methods or paths pass through unchanged.
  """
  def call(conn, _opts) do
    conn =
      conn
      |> fetch_query_params()
      |> fetch_session()

    case {conn.method, conn.path_info} do
      {"GET", [provider]} ->
        Amur.Controller.request(conn, %{"provider" => provider})

      {"GET", [provider, "callback"]} ->
        Amur.Controller.callback(conn, Map.put(conn.params, "provider", provider))

      _ ->
        conn
    end
  end
end

defmodule Amur.Router do
  @moduledoc """
  Plug router for the Amur OAuth flow.

  Mount it under your router, for example with `forward "/auth", Amur.Router`
  (in Phoenix, inside a browser pipeline and with `alias: false`). It exposes,
  relative to the mount point:

    * `GET /auth` - the sign-in page listing the configured providers
    * `GET /auth/:provider` - start the OAuth flow
    * `GET /auth/:provider/callback` - handle the provider callback

  The sign-in page and its assets are served from Amur's own `priv/` directory,
  so the same routes work in Phoenix and in a standalone `Plug.Router` without
  copying any files into the host application.
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
      {"GET", []} ->
        Amur.Page.render(conn)

      {"GET", [segment]} ->
        dispatch_segment(conn, segment)

      {"GET", [provider, "callback"]} ->
        Amur.Controller.callback(conn, Map.put(conn.params, "provider", provider))

      _ ->
        conn
    end
  end

  # A single trailing segment is either a static asset (matched by extension)
  # or a provider name, so the two routes stay distinct.
  defp dispatch_segment(conn, segment) do
    if asset?(segment) do
      Amur.Page.asset(conn, [segment]) || conn
    else
      Amur.Controller.request(conn, %{"provider" => segment})
    end
  end

  defp asset?(segment) do
    String.ends_with?(segment, ".css") or String.ends_with?(segment, ".svg")
  end
end

defmodule Amur.Router do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn =
      conn
      |> fetch_query_params()
      |> fetch_session()

    case {conn.method, conn.path_info} do
      {"GET", ["logout"]} ->
        Amur.Controller.logout(conn, %{})

      {"GET", [provider]} ->
        Amur.Controller.request(conn, %{"provider" => provider})

      {"GET", [provider, "callback"]} ->
        Amur.Controller.callback(conn, Map.put(conn.params, "provider", provider))

      _ ->
        conn
    end
  end
end

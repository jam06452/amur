defmodule Amur.Router do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    conn =
      if Keyword.get(opts, :fetch_session, true) do
        conn
        |> fetch_query_params()
        |> fetch_session()
      else
        fetch_query_params(conn)
      end

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

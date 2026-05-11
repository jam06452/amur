defmodule Amur.ControllerTest do
  use ExUnit.Case, async: true

  defmodule Router do
    use Plug.Router

    plug(:match)
    plug(:dispatch)

    get "/" do
      send_resp(conn, 200, "home")
    end

    forward("/auth", to: Amur.Router)
  end

  test "default_failure redirects to /" do
    conn =
      Plug.Test.conn(:get, "/")
      |> Plug.Test.init_test_session(%{})

    conn = Amur.Controller.default_failure(conn, :some_reason)

    assert conn.status == 302
    assert Plug.Conn.get_resp_header(conn, "location") == ["/"]
  end

  test "logout clears amur session params and redirects to /" do
    conn =
      Plug.Test.conn(:get, "/")
      |> Plug.Test.init_test_session(%{amur_session_params: %{code_verifier: "abc"}})

    conn = Amur.Controller.logout(conn, %{})

    assert Plug.Conn.get_session(conn, :amur_session_params) == nil
    assert conn.status == 302
    assert Plug.Conn.get_resp_header(conn, "location") == ["/"]
  end

  test "logout route resolves before provider route" do
    conn =
      Plug.Test.conn(:get, "/auth/logout")
      |> Plug.Test.init_test_session(%{})
      |> Router.call(Router.init([]))

    assert conn.status == 302
    assert Plug.Conn.get_resp_header(conn, "location") == ["/"]
  end
end

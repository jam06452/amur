defmodule Amur.ControllerTest do
  use ExUnit.Case, async: true

  test "default_failure redirects to /" do
    conn =
      Plug.Test.conn(:get, "/")
      |> Plug.Test.init_test_session(%{})

    conn = Amur.Controller.default_failure(conn, :some_reason)

    assert conn.status == 302
    assert Plug.Conn.get_resp_header(conn, "location") == ["/"]
  end

  test "callback clears amur session params" do
    conn =
      Plug.Test.conn(:get, "/")
      |> Plug.Test.init_test_session(%{
        amur_session_params: %{state: "state", code_verifier: "abc"}
      })

    conn = Amur.Controller.callback(conn, %{"provider" => "github"})

    assert Plug.Conn.get_session(conn, :amur_session_params) == nil
  end
end

defmodule Amur.RouterTest do
  use ExUnit.Case, async: false

  setup do
    previous = %{
      providers: Application.get_env(:amur, :providers),
      on_success: Application.get_env(:amur, :on_success),
      on_failure: Application.get_env(:amur, :on_failure)
    }

    Application.put_env(:amur, :providers, router: Amur.RouterTest.Provider)
    Application.put_env(:amur, :on_success, fn conn, _context -> conn end)
    Application.put_env(:amur, :on_failure, fn conn, _reason -> conn end)

    on_exit(fn ->
      for {key, value} <- previous do
        if is_nil(value),
          do: Application.delete_env(:amur, key),
          else: Application.put_env(:amur, key, value)
      end
    end)

    :ok
  end

  test "init returns options unchanged" do
    assert Amur.Router.init(foo: :bar) == [foo: :bar]
  end

  test "GET provider route fetches query params and session and starts request" do
    conn =
      Plug.Test.conn(:get, "/auth/router?return_to=%2Fhome")
      |> Plug.Test.init_test_session(%{})

    conn = Amur.Router.call(%{conn | path_info: ["router"]}, [])

    assert conn.status == 302
    assert Plug.Conn.get_resp_header(conn, "location") == ["https://provider.example/authorize"]
    assert Plug.Conn.get_session(conn, :amur_session_params) == %{state: "router-state"}
    assert conn.query_params == %{"return_to" => "/home"}
  end

  test "GET callback route passes query params and clears session" do
    conn =
      Plug.Test.conn(:get, "/auth/router/callback?code=abc")
      |> Plug.Test.init_test_session(%{amur_session_params: %{state: "router-state"}})

    conn = Amur.Router.call(%{conn | path_info: ["router", "callback"]}, [])

    assert Plug.Conn.get_session(conn, :amur_session_params) == nil
  end

  test "unsupported method and path pass through unchanged" do
    post =
      Plug.Test.conn(:post, "/auth/router")
      |> Plug.Test.init_test_session(%{})
      |> Amur.Router.call([])

    unknown =
      Plug.Test.conn(:get, "/auth/router/extra/path")
      |> Plug.Test.init_test_session(%{})
      |> Amur.Router.call([])

    assert post.status == nil
    assert unknown.status == nil
  end

  defmodule Strategy do
    def authorize_url(_config),
      do:
        {:ok,
         %{url: "https://provider.example/authorize", session_params: %{state: "router-state"}}}

    def callback(_config, _params),
      do: {:ok, %{user: %{"id" => "1"}, token: %{access_token: "token"}}}
  end

  defmodule Provider do
    use Amur.Provider
    def strategy, do: Amur.RouterTest.Strategy
    def base_config, do: []
    def normalize_user(user), do: %{uid: user["id"]}
  end
end

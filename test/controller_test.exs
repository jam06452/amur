defmodule Amur.ControllerTest do
  use ExUnit.Case, async: false

  setup do
    previous =
      for key <- [:providers, :on_success, :on_failure],
          into: %{},
          do: {key, Application.get_env(:amur, key)}

    Application.put_env(:amur, :providers, fake: Amur.ControllerTest.Provider)

    Application.put_env(:amur, :on_success, fn conn, context ->
      send(self(), {:success, context})
      conn
    end)

    Application.put_env(:amur, :on_failure, fn conn, reason ->
      send(self(), {:failure, reason})
      conn
    end)

    on_exit(fn ->
      for {key, value} <- previous do
        if is_nil(value),
          do: Application.delete_env(:amur, key),
          else: Application.put_env(:amur, key, value)
      end
    end)

    :ok
  end

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

  test "request stores strategy session params and redirects" do
    conn = Plug.Test.conn(:get, "/auth/fake") |> Plug.Test.init_test_session(%{})

    conn = Amur.Controller.request(conn, %{"provider" => "fake"})

    assert conn.status == 302
    assert Plug.Conn.get_resp_header(conn, "location") == ["https://provider.example/authorize"]
    assert Plug.Conn.get_session(conn, :amur_session_params) == %{state: "expected"}
  end

  test "request invokes failure callback for unknown provider" do
    conn = Amur.Controller.request(Plug.Test.conn(:get, "/"), %{"provider" => "missing"})

    assert_receive {:failure, :unknown_provider}
    assert conn.status == nil
  end

  test "request invokes failure callback when authorization fails" do
    Application.put_env(:amur, :providers, failing: Amur.ControllerTest.FailingProvider)
    conn = Amur.Controller.request(Plug.Test.conn(:get, "/"), %{"provider" => "failing"})

    assert_receive {:failure, :authorization_failed}
    assert conn.status == nil
  end

  test "callback normalizes user, adds provider, and invokes success callback" do
    conn =
      Plug.Test.conn(:get, "/")
      |> Plug.Test.init_test_session(%{amur_session_params: %{state: "expected"}})

    conn = Amur.Controller.callback(conn, %{"provider" => "fake", "code" => "code"})

    assert_receive {:success, %{user: user, token: %{access_token: "token"}}}
    assert user == %{uid: "user-1", email: "user@example.com", provider: "fake"}
    assert Plug.Conn.get_session(conn, :amur_session_params) == nil
  end

  test "completes authorize redirect, callback, and success as one flow" do
    conn =
      Plug.Test.conn(:get, "/auth/fake")
      |> Plug.Test.init_test_session(%{})

    redirected = Amur.Controller.request(conn, %{"provider" => "fake"})

    assert redirected.status == 302
    assert redirected.halted

    assert Plug.Conn.get_resp_header(redirected, "location") == [
             "https://provider.example/authorize"
           ]

    callback_conn =
      Plug.Test.conn(:get, "/auth/fake/callback?code=oauth-code")
      |> Plug.Test.init_test_session(%{
        amur_session_params: Plug.Conn.get_session(redirected, :amur_session_params)
      })

    completed =
      Amur.Controller.callback(callback_conn, %{"provider" => "fake", "code" => "oauth-code"})

    assert_receive {:success, %{user: %{provider: "fake", uid: "user-1"}, token: token}}
    assert token == %{access_token: "token"}
    assert Plug.Conn.get_session(completed, :amur_session_params) == nil
  end

  test "callback rejects missing, empty, and malformed session state" do
    for session_params <- [nil, %{}, %{state: ""}, [state: ""], [code_verifier: "x"]] do
      conn =
        Plug.Test.conn(:get, "/")
        |> Plug.Test.init_test_session(%{amur_session_params: session_params})

      conn = Amur.Controller.callback(conn, %{"provider" => "fake"})

      assert_receive {:failure, :invalid_session_params}
      assert Plug.Conn.get_session(conn, :amur_session_params) == nil
    end
  end

  test "callback invokes failure callback when strategy fails" do
    Application.put_env(:amur, :providers, failing: Amur.ControllerTest.FailingProvider)

    conn =
      Plug.Test.conn(:get, "/")
      |> Plug.Test.init_test_session(%{amur_session_params: %{state: "expected"}})

    Amur.Controller.callback(conn, %{"provider" => "failing"})

    assert_receive {:failure, :callback_failed}
  end

  test "default failure halts the redirected response" do
    conn = Amur.Controller.default_failure(Plug.Test.conn(:get, "/"), :reason)

    assert conn.halted
    assert conn.status == 302
  end

  defmodule Strategy do
    def authorize_url(_config),
      do:
        {:ok, %{url: "https://provider.example/authorize", session_params: %{state: "expected"}}}

    def callback(_config, _params),
      do:
        {:ok,
         %{
           user: %{"id" => "user-1", "email" => "user@example.com"},
           token: %{access_token: "token"}
         }}
  end

  defmodule FailingStrategy do
    def authorize_url(_config), do: {:error, :authorization_failed}
    def callback(_config, _params), do: {:error, :callback_failed}
  end

  defmodule Provider do
    use Amur.Provider
    def strategy, do: Amur.ControllerTest.Strategy
    def base_config, do: []
    def normalize_user(user), do: %{uid: user["id"], email: user["email"]}
  end

  defmodule FailingProvider do
    use Amur.Provider
    def strategy, do: Amur.ControllerTest.FailingStrategy
    def base_config, do: []
    def normalize_user(user), do: user
  end
end

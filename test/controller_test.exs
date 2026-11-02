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

  test "callback reports an atom provider as a string" do
    conn =
      Plug.Test.conn(:get, "/")
      |> Plug.Test.init_test_session(%{amur_session_params: %{state: "expected"}})

    Amur.Controller.callback(conn, %{"provider" => :fake})

    assert_receive {:success, %{user: %{provider: "fake"}}}
  end

  test "success and failure callbacks accept MFA tuples and extra arguments" do
    Application.put_env(:amur, :on_success, {__MODULE__, :record_callback, [:success]})
    Application.put_env(:amur, :on_failure, {__MODULE__, :record_callback, []})

    conn =
      Plug.Test.conn(:get, "/")
      |> Plug.Test.init_test_session(%{amur_session_params: %{state: "expected"}})

    assert %Plug.Conn{} = Amur.Controller.callback(conn, %{"provider" => "fake"})
    assert_receive {:mfa_callback, :success, %{user: %{provider: "fake"}}}

    assert %Plug.Conn{} =
             Amur.Controller.request(Plug.Test.conn(:get, "/"), %{"provider" => "missing"})

    assert_receive {:mfa_callback, :failure, :unknown_provider}
  end

  test "callback converts valid keyword session params for Assent OAuth2" do
    Application.put_env(:amur, :providers, oauth2: Amur.ControllerTest.OAuth2Provider)

    conn =
      Plug.Test.conn(:get, "/")
      |> Plug.Test.init_test_session(%{amur_session_params: [state: "expected"]})

    conn =
      Amur.Controller.callback(conn, %{
        "provider" => "oauth2",
        "state" => "expected",
        "code" => "code"
      })

    assert_receive {:success, %{user: %{uid: "user-1"}, token: %{"access_token" => "token"}}}
    assert Plug.Conn.get_session(conn, :amur_session_params) == nil
  end

  test "Assent OAuth2 rejects malformed protocol parameters without raising" do
    Application.put_env(:amur, :providers, oauth2: Amur.ControllerTest.OAuth2Provider)

    for {field, value} <- [
          {"state", ["expected"]},
          {"code", ["code"]},
          {"code", %{"nested" => "code"}},
          {"error", ["access_denied"]},
          {"error_description", %{"nested" => "error"}}
        ] do
      params =
        %{"provider" => "oauth2", "state" => "expected", "code" => "code"}
        |> Map.put(field, value)

      conn =
        Plug.Test.conn(:get, "/")
        |> Plug.Test.init_test_session(%{amur_session_params: %{state: "expected"}})
        |> Amur.Controller.callback(params)

      if field == "state",
        do: assert_receive({:failure, %Assent.CallbackCSRFError{key: "state"}}),
        else: assert_receive({:failure, %Assent.CallbackError{}})

      assert Plug.Conn.get_session(conn, :amur_session_params) == nil
      refute_receive {:success, _context}, 0
    end
  end

  test "Assent OAuth1 rejects malformed token and verifier parameters without raising" do
    Application.put_env(:amur, :providers, twitter: [])

    for field <- ["oauth_token", "oauth_verifier", "denied"] do
      params = %{
        "provider" => "twitter",
        "oauth_token" => "token",
        "oauth_verifier" => "verifier"
      }

      params = Map.put(params, field, ["malformed"])

      conn =
        Plug.Test.conn(:get, "/")
        |> Plug.Test.init_test_session(%{amur_session_params: %{oauth_token_secret: "secret"}})
        |> Amur.Controller.callback(params)

      assert_receive {:failure, %Assent.CallbackError{}}
      assert Plug.Conn.get_session(conn, :amur_session_params) == nil
      refute_receive {:success, _context}, 0
    end
  end

  test "Twitter completes an OAuth1 flow using its request token secret" do
    Application.put_env(:amur, :providers,
      twitter: [
        consumer_key: "key",
        consumer_secret: "secret",
        http_adapter: Amur.ControllerTest.HTTPAdapter
      ]
    )

    conn = Plug.Test.conn(:get, "/auth/twitter") |> Plug.Test.init_test_session(%{})
    redirected = Amur.Controller.request(conn, %{"provider" => "twitter"})

    assert Plug.Conn.get_session(redirected, :amur_session_params) == %{
             oauth_token_secret: "request-secret"
           }

    conn =
      Plug.Test.conn(:get, "/auth/twitter/callback")
      |> Plug.Test.init_test_session(%{
        amur_session_params: Plug.Conn.get_session(redirected, :amur_session_params)
      })

    conn =
      Amur.Controller.callback(conn, %{
        "provider" => "twitter",
        "oauth_token" => "request-token",
        "oauth_verifier" => "verifier"
      })

    assert_receive {:success,
                    %{
                      user: %{provider: "twitter", uid: "user-1"},
                      token: %{"oauth_token" => "access-token"}
                    }}

    assert Plug.Conn.get_session(conn, :amur_session_params) == nil
  end

  test "Twitter rejects missing and malformed request token secrets" do
    Application.put_env(:amur, :providers, twitter: [])

    for session_params <- [
          nil,
          %{},
          %{state: "expected"},
          %{oauth_token_secret: ""},
          %{oauth_token_secret: 1}
        ] do
      conn =
        Plug.Test.conn(:get, "/")
        |> Plug.Test.init_test_session(%{amur_session_params: session_params})

      conn = Amur.Controller.callback(conn, %{"provider" => "twitter"})

      assert_receive {:failure, :invalid_session_params}
      assert Plug.Conn.get_session(conn, :amur_session_params) == nil
    end
  end

  test "a custom OAuth1 strategy validates its request token secret" do
    Application.put_env(:amur, :providers, oauth1: Amur.ControllerTest.OAuth1Provider)

    conn =
      Plug.Test.conn(:get, "/auth/oauth1")
      |> Plug.Test.init_test_session(%{})
      |> Amur.Controller.request(%{"provider" => "oauth1"})

    conn =
      Plug.Test.conn(:get, "/auth/oauth1/callback")
      |> Plug.Test.init_test_session(%{
        amur_session_params: Plug.Conn.get_session(conn, :amur_session_params)
      })
      |> Amur.Controller.callback(%{
        "provider" => "oauth1",
        "oauth_token" => "request-token",
        "oauth_verifier" => "verifier"
      })

    assert_receive {:success, %{user: %{provider: "oauth1", uid: "user-1"}}}
    assert Plug.Conn.get_session(conn, :amur_session_params) == nil
  end

  test "Telegram redirects with session state and verifies signed user data without a token" do
    configure_telegram()
    {redirected, state} = telegram_request()

    assert redirected.status == 302
    assert is_binary(state) and state != ""

    callback_params =
      signed_telegram_params()
      |> Map.merge(%{
        "provider" => "telegram",
        "amur_state" => state,
        "continue" => "/home"
      })

    conn =
      Plug.Test.conn(:get, "/auth/telegram/callback")
      |> Plug.Test.init_test_session(%{
        amur_session_params: Plug.Conn.get_session(redirected, :amur_session_params)
      })
      |> Amur.Controller.callback(callback_params)

    assert_receive {:success,
                    %{user: %{provider: "telegram", uid: "42", name: "Alice"}, token: nil}}

    assert Plug.Conn.get_session(conn, :amur_session_params) == nil
  end

  test "Apple takes identity claims from the signed token, not the user form field" do
    configure_apple()

    params = %{
      "provider" => "apple",
      "state" => "expected",
      "code" => "code",
      "user" =>
        Jason.encode!(%{
          "sub" => "victim",
          "email" => "victim@example.com",
          "name" => %{"firstName" => "Alice", "lastName" => "Smith"}
        })
    }

    conn =
      Plug.Test.conn(:post, "/auth/apple/callback")
      |> Plug.Test.init_test_session(%{amur_session_params: %{state: "expected"}})
      |> Amur.Controller.callback(params)

    assert_receive {:success,
                    %{
                      user: %{
                        uid: "authenticated-user",
                        email: "signed@example.com",
                        name: "Alice Smith"
                      }
                    }}

    assert Plug.Conn.get_session(conn, :amur_session_params) == nil
  end

  test "Apple rejects malformed user JSON without raising" do
    configure_apple()

    for user <- [
          "null",
          "[]",
          "1",
          ~s({"name":null}),
          ~s({"name":[]}),
          ~s({"name":{"firstName":{}}})
        ] do
      conn =
        Plug.Test.conn(:post, "/auth/apple/callback")
        |> Plug.Test.init_test_session(%{amur_session_params: %{state: "expected"}})
        |> Amur.Controller.callback(%{
          "provider" => "apple",
          "state" => "expected",
          "code" => "code",
          "user" => user
        })

      assert_receive {:failure, %Assent.CallbackError{}}
      assert Plug.Conn.get_session(conn, :amur_session_params) == nil
      refute_receive {:success, _context}, 0
    end
  end

  test "Telegram rejects missing, malformed, and incorrect callback state" do
    configure_telegram()

    for provided_state <- [nil, "", ["malformed"], "wrong-state"] do
      {redirected, _state} = telegram_request()

      conn =
        Plug.Test.conn(:get, "/auth/telegram/callback")
        |> Plug.Test.init_test_session(%{
          amur_session_params: Plug.Conn.get_session(redirected, :amur_session_params)
        })

      conn =
        Amur.Controller.callback(conn, %{
          "provider" => "telegram",
          "amur_state" => provided_state
        })

      assert_receive {:failure, %Assent.CallbackCSRFError{key: "amur_state"}}
      assert Plug.Conn.get_session(conn, :amur_session_params) == nil
      refute_receive {:success, _context}, 0
    end
  end

  test "Telegram excludes nested return URL query parameters from its signature" do
    configure_telegram()
    [{:telegram, config}] = Application.get_env(:amur, :providers)

    Application.put_env(:amur, :providers,
      telegram:
        Keyword.put(
          config,
          :return_to,
          "https://app.example/telegram/return?continue=%2Fhome&context[page]=login"
        )
    )

    {redirected, state} = telegram_request()

    query =
      signed_telegram_params()
      |> Map.put("amur_state", state)
      |> URI.encode_query()

    conn =
      Plug.Test.conn(:get, "/auth/telegram/callback?context[page]=login&" <> query)
      |> Plug.Test.init_test_session(%{
        amur_session_params: Plug.Conn.get_session(redirected, :amur_session_params)
      })

    Amur.Router.call(%{conn | path_info: ["telegram", "callback"]}, [])

    assert_receive {:success, %{user: %{uid: "42"}, token: nil}}
  end

  test "Telegram preserves signature failures and requires an initiated session" do
    configure_telegram()
    {redirected, state} = telegram_request()

    conn =
      Plug.Test.conn(:get, "/auth/telegram/callback")
      |> Plug.Test.init_test_session(%{
        amur_session_params: Plug.Conn.get_session(redirected, :amur_session_params)
      })

    params =
      signed_telegram_params()
      |> Map.merge(%{"provider" => "telegram", "amur_state" => state, "hash" => "invalid"})

    conn = Amur.Controller.callback(conn, params)

    assert_receive {:failure,
                    %Assent.CallbackError{message: "Authorization request has an invalid hash"}}

    assert Plug.Conn.get_session(conn, :amur_session_params) == nil

    conn = Plug.Test.conn(:get, "/") |> Plug.Test.init_test_session(%{})
    Amur.Controller.callback(conn, params)
    assert_receive {:failure, :invalid_session_params}
    refute_receive {:success, _context}, 0
  end

  test "Telegram rejects malformed signed payload fields without raising" do
    configure_telegram()

    for malformed <- [
          %{"auth_date" => "not-an-integer"},
          %{"auth_date" => ["malformed"]},
          %{"hash" => ["malformed"]},
          %{"first_name" => %{"nested" => "value"}}
        ] do
      {redirected, state} = telegram_request()

      params =
        signed_telegram_params()
        |> Map.merge(malformed)
        |> Map.merge(%{"provider" => "telegram", "amur_state" => state})

      conn =
        Plug.Test.conn(:get, "/auth/telegram/callback")
        |> Plug.Test.init_test_session(%{
          amur_session_params: Plug.Conn.get_session(redirected, :amur_session_params)
        })
        |> Amur.Controller.callback(params)

      assert_receive {:failure, %Assent.CallbackError{}}
      assert Plug.Conn.get_session(conn, :amur_session_params) == nil
    end
  end

  test "Telegram accepts a valid keyword session" do
    configure_telegram()
    {redirected, state} = telegram_request()
    session_params = Plug.Conn.get_session(redirected, :amur_session_params) |> Map.to_list()

    params =
      signed_telegram_params() |> Map.merge(%{"provider" => "telegram", "amur_state" => state})

    conn =
      Plug.Test.conn(:get, "/auth/telegram/callback")
      |> Plug.Test.init_test_session(%{amur_session_params: session_params})
      |> Amur.Controller.callback(params)

    assert_receive {:success, %{user: %{provider: "telegram"}, token: nil}}
    assert Plug.Conn.get_session(conn, :amur_session_params) == nil
  end

  test "Telegram rejects malformed mini app data without raising" do
    configure_telegram()
    [{:telegram, config}] = Application.get_env(:amur, :providers)

    Application.put_env(:amur, :providers,
      telegram: Keyword.put(config, :authorization_channel, :web_mini_app)
    )

    for init_data <- [["malformed"], "auth_date=invalid&hash=invalid"] do
      {redirected, state} = telegram_request()

      conn =
        Plug.Test.conn(:get, "/auth/telegram/callback")
        |> Plug.Test.init_test_session(%{
          amur_session_params: Plug.Conn.get_session(redirected, :amur_session_params)
        })
        |> Amur.Controller.callback(%{
          "provider" => "telegram",
          "amur_state" => state,
          "init_data" => init_data
        })

      assert_receive {:failure, %Assent.CallbackError{}}
      assert Plug.Conn.get_session(conn, :amur_session_params) == nil
    end
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
    for session_params <- [
          nil,
          %{},
          %{state: ""},
          [state: ""],
          [code_verifier: "x"],
          [state: false],
          [state: 1],
          [state: []],
          [{:state, "expected"}, :malformed]
        ] do
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

  def record_callback(conn, payload, kind \\ :failure) do
    send(self(), {:mfa_callback, kind, payload})
    conn
  end

  defp configure_telegram do
    Application.put_env(:amur, :providers,
      telegram: [
        bot_token: "123:secret",
        origin: "https://app.example",
        return_to: "https://app.example/auth/telegram/callback?continue=%2Fhome"
      ]
    )
  end

  defp configure_apple do
    private_key = :public_key.generate_key({:rsa, 1024, 65_537})
    {:RSAPrivateKey, _, modulus, exponent, _, _, _, _, _, _, _} = private_key
    pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, private_key)])
    now = System.system_time(:second)

    {:ok, token} =
      Assent.JWTAdapter.sign(
        %{
          "iss" => "https://appleid.apple.com",
          "sub" => "authenticated-user",
          "aud" => "client",
          "iat" => now,
          "exp" => now + 60,
          "email" => "signed@example.com"
        },
        "RS256",
        pem
      )

    Process.put(:apple_token, token)

    Process.put(:apple_public_key, %{
      "kty" => "RSA",
      "n" => Base.url_encode64(:binary.encode_unsigned(modulus), padding: false),
      "e" => Base.url_encode64(:binary.encode_unsigned(exponent), padding: false)
    })

    signing_key = :public_key.generate_key({:namedCurve, :secp256r1})

    signing_pem =
      :public_key.pem_encode([:public_key.pem_entry_encode(:ECPrivateKey, signing_key)])

    Application.put_env(:amur, :providers,
      apple: [
        client_id: "client",
        team_id: "team",
        private_key_id: "key",
        private_key: signing_pem,
        http_adapter: Amur.ControllerTest.AppleHTTPAdapter
      ]
    )
  end

  defmodule AppleHTTPAdapter do
    @behaviour Assent.HTTPAdapter

    @impl true
    def request(_method, url, _body, _headers, _opts) do
      body =
        case URI.parse(url).path do
          "/auth/token" ->
            %{"access_token" => "token", "id_token" => Process.get(:apple_token)}

          "/auth/keys" ->
            %{"keys" => [Process.get(:apple_public_key)]}
        end

      {:ok, %Assent.HTTPAdapter.HTTPResponse{status: 200, body: body}}
    end
  end

  defp telegram_request do
    conn = Plug.Test.conn(:get, "/auth/telegram") |> Plug.Test.init_test_session(%{})
    redirected = Amur.Controller.request(conn, %{"provider" => "telegram"})
    [location] = Plug.Conn.get_resp_header(redirected, "location")
    params = location |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    return_params = params["return_to"] |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    assert return_params["continue"] == "/home"
    {redirected, return_params["amur_state"]}
  end

  defp signed_telegram_params do
    params = %{
      "id" => "42",
      "first_name" => "Alice",
      "auth_date" => Integer.to_string(System.system_time(:second))
    }

    data =
      params
      |> Enum.map(fn {key, value} -> "#{key}=#{value}" end)
      |> Enum.sort()
      |> Enum.join("\n")

    secret = :crypto.hash(:sha256, "123:secret")
    hash = :crypto.mac(:hmac, :sha256, secret, data) |> Base.encode16(case: :lower)
    Map.put(params, "hash", hash)
  end

  defmodule HTTPAdapter do
    @behaviour Assent.HTTPAdapter

    @impl true
    def request(_method, url, _body, _headers, _opts) do
      body =
        case URI.parse(url).path do
          "/oauth/request_token" ->
            %{"oauth_token" => "request-token", "oauth_token_secret" => "request-secret"}

          "/oauth/access_token" ->
            %{"oauth_token" => "access-token", "oauth_token_secret" => "access-secret"}

          "/oauth/token" ->
            %{"access_token" => "token"}

          "/1.1/account/verify_credentials.json" ->
            %{"id" => "user-1", "name" => "User"}

          "/user" ->
            %{"id" => "user-1"}
        end

      {:ok, %Assent.HTTPAdapter.HTTPResponse{status: 200, body: body}}
    end
  end

  defmodule OAuth2Provider do
    use Amur.Provider
    def strategy, do: Assent.Strategy.OAuth2

    def base_config do
      [
        base_url: "https://provider.example",
        client_id: "id",
        user_url: "/user",
        http_adapter: Amur.ControllerTest.HTTPAdapter
      ]
    end

    def normalize_user(user), do: %{uid: user["id"]}
  end

  defmodule OAuth1Strategy do
    use Assent.Strategy.OAuth.Base

    @impl true
    def default_config(_config) do
      [
        base_url: "https://provider.example",
        request_token_url: "/oauth/request_token",
        access_token_url: "/oauth/access_token",
        consumer_key: "key",
        consumer_secret: "secret",
        http_adapter: Amur.ControllerTest.HTTPAdapter
      ]
    end

    @impl true
    def fetch_user(_config, _token), do: {:ok, %{"id" => "user-1"}}

    @impl true
    def normalize(_config, user), do: {:ok, %{"sub" => user["id"]}}
  end

  defmodule OAuth1Provider do
    use Amur.Provider
    def strategy, do: Amur.ControllerTest.OAuth1Strategy
    def base_config, do: []
    def normalize_user(user), do: %{uid: user["sub"]}
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

  test "Apple supports absent and partial first-login names and an explicit opt-out" do
    configure_apple()

    for {user, name} <- [
          {nil, " "},
          {%{"email" => "forged@example.com"}, " "},
          {%{"name" => %{"firstName" => "Alice"}}, "Alice "},
          {%{"name" => %{"lastName" => "Smith"}}, " Smith"}
        ] do
      params = %{"provider" => "apple", "state" => "expected", "code" => "code"}
      params = if user, do: Map.put(params, "user", Jason.encode!(user)), else: params

      Plug.Test.conn(:post, "/auth/apple/callback")
      |> Plug.Test.init_test_session(%{amur_session_params: %{state: "expected"}})
      |> Amur.Controller.callback(params)

      assert_receive {:success,
                      %{
                        user: %{
                          name: ^name,
                          uid: "authenticated-user",
                          email: "signed@example.com"
                        }
                      }}
    end

    [{:apple, config}] = Application.get_env(:amur, :providers)

    Application.put_env(:amur, :providers,
      apple: Keyword.put(config, :include_unverified_name, false)
    )

    Plug.Test.conn(:post, "/auth/apple/callback")
    |> Plug.Test.init_test_session(%{amur_session_params: %{state: "expected"}})
    |> Amur.Controller.callback(%{
      "provider" => "apple",
      "state" => "expected",
      "code" => "code",
      "user" => Jason.encode!(%{"name" => %{"firstName" => "Alice"}})
    })

    assert_receive {:success, %{user: %{name: " ", uid: "authenticated-user"}}}
  end

  test "Telegram accepts integer timestamps with a valid signature" do
    configure_telegram()
    params = signed_telegram_params()
    params = Map.update!(params, "auth_date", &String.to_integer/1)

    conn =
      Plug.Test.conn(:get, "/")
      |> Plug.Test.init_test_session(%{amur_session_params: %{state: "expected"}})
      |> Amur.Controller.callback(
        Map.merge(params, %{"provider" => "telegram", "amur_state" => "expected"})
      )

    assert_receive {:success, %{user: %{uid: "42"}, token: nil}}
    assert Plug.Conn.get_session(conn, :amur_session_params) == nil
  end

  test "Telegram reports missing mini app data and unsupported channels" do
    for {channel, message} <- [
          {:web_mini_app, "init_data"},
          {:unsupported, "Invalid `:authorization_channel` value"}
        ] do
      configure_telegram()
      [{:telegram, config}] = Application.get_env(:amur, :providers)

      Application.put_env(:amur, :providers,
        telegram: Keyword.put(config, :authorization_channel, channel)
      )

      conn =
        Plug.Test.conn(:get, "/")
        |> Plug.Test.init_test_session(%{amur_session_params: %{state: "expected"}})
        |> Amur.Controller.callback(%{"provider" => "telegram", "amur_state" => "expected"})

      assert_receive {:failure, error}
      assert Exception.message(error) =~ message
      assert Plug.Conn.get_session(conn, :amur_session_params) == nil
    end
  end

  defmodule BareOAuthProvider do
    use Amur.Provider
    def strategy, do: Assent.Strategy.OAuth
    def base_config, do: []
    def normalize_user(user), do: user
  end

  defmodule MissingStrategyProvider do
    use Amur.Provider
    def strategy, do: Amur.NonexistentStrategy
    def base_config, do: []
    def normalize_user(user), do: user
  end

  test "bare OAuth and unavailable strategies reject invalid session state" do
    for provider <- [BareOAuthProvider, MissingStrategyProvider] do
      Application.put_env(:amur, :providers, custom: provider)

      conn =
        Plug.Test.conn(:get, "/")
        |> Plug.Test.init_test_session(%{amur_session_params: %{}})
        |> Amur.Controller.callback(%{"provider" => "custom"})

      assert_receive {:failure, :invalid_session_params}
      assert Plug.Conn.get_session(conn, :amur_session_params) == nil
    end
  end
end

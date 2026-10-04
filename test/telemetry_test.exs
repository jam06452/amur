defmodule Amur.TelemetryTest do
  use ExUnit.Case, async: false

  alias Amur.Telemetry

  @handler_id "amur-telemetry-test"

  setup do
    previous =
      for key <- [:providers, :on_success, :on_failure],
          into: %{},
          do: {key, Application.get_env(:amur, key)}

    Application.put_env(:amur, :providers, fake: Amur.TelemetryTest.Provider)

    Application.put_env(:amur, :on_success, fn conn, context ->
      send(self(), {:success, context})
      conn
    end)

    Application.put_env(:amur, :on_failure, fn conn, reason ->
      send(self(), {:failure, reason})
      conn
    end)

    :telemetry.attach_many(
      @handler_id,
      [
        [:amur, :request, :start],
        [:amur, :request, :stop],
        [:amur, :request, :exception],
        [:amur, :callback, :start],
        [:amur, :callback, :stop],
        [:amur, :callback, :exception]
      ],
      &__MODULE__.handle_event/4,
      self()
    )

    on_exit(fn ->
      :telemetry.detach(@handler_id)

      for {key, value} <- previous do
        if is_nil(value),
          do: Application.delete_env(:amur, key),
          else: Application.put_env(:amur, key, value)
      end
    end)

    :ok
  end

  # Forwards every event to the test process so assertions can match on it.
  def handle_event(event, measurements, metadata, pid) do
    send(pid, {:telemetry, event, measurements, metadata})
  end

  defp start_conn do
    Plug.Test.conn(:get, "/auth/fake") |> Plug.Test.init_test_session(%{})
  end

  defp callback_conn(session_params \\ %{state: "expected"}) do
    Plug.Test.conn(:get, "/auth/fake/callback?code=code")
    |> Plug.Test.init_test_session(%{amur_session_params: session_params})
  end

  describe "request span" do
    test "emits start and stop with provider and result on success" do
      Amur.Controller.request(start_conn(), %{"provider" => "fake"})

      assert_receive {:telemetry, [:amur, :request, :start], start_measurements,
                      %{provider: :fake} = start_metadata}

      assert is_integer(start_measurements.system_time)
      refute Map.has_key?(start_metadata, :strategy)

      assert_receive {:telemetry, [:amur, :request, :stop], stop_measurements,
                      %{provider: :fake, result: :ok} = stop_metadata}

      assert is_integer(stop_measurements.duration)
      assert is_integer(stop_measurements.monotonic_time)
      refute Map.has_key?(stop_measurements, :system_time)
      assert stop_metadata.strategy == Amur.TelemetryTest.Strategy
      refute Map.has_key?(stop_metadata, :reason)
    end

    test "emits a matching start and stop pair for an unknown provider" do
      Amur.Controller.request(Plug.Test.conn(:get, "/"), %{"provider" => "missing"})

      assert_receive {:telemetry, [:amur, :request, :start], _measurements, %{provider: nil}}
      assert_receive {:telemetry, [:amur, :request, :stop], _measurements, metadata}

      assert metadata.provider == nil
      assert metadata.result == :error
      assert metadata.reason == :unknown_provider
    end

    test "sanitizes the reason when the strategy fails" do
      Application.put_env(:amur, :providers, failing: Amur.TelemetryTest.FailingProvider)

      Amur.Controller.request(Plug.Test.conn(:get, "/"), %{"provider" => "failing"})

      assert_receive {:telemetry, [:amur, :request, :stop], _measurements, metadata}
      assert metadata.result == :error
      assert metadata.reason == :provider_error
    end

    test "includes strategy on an error stop when the provider resolved" do
      # The provider resolved and the strategy ran, so a handler can rely on
      # `strategy` being present even though the request failed.
      Application.put_env(:amur, :providers, failing: Amur.TelemetryTest.FailingProvider)

      Amur.Controller.request(Plug.Test.conn(:get, "/"), %{"provider" => "failing"})

      assert_receive {:telemetry, [:amur, :request, :stop], _measurements, metadata}
      assert metadata.strategy == Amur.TelemetryTest.FailingStrategy
    end

    test "omits strategy on an error stop when the provider did not resolve" do
      Amur.Controller.request(Plug.Test.conn(:get, "/"), %{"provider" => "missing"})

      assert_receive {:telemetry, [:amur, :request, :stop], _measurements, metadata}
      assert metadata.result == :error
      refute Map.has_key?(metadata, :strategy)
    end
  end

  describe "callback span" do
    test "emits start and stop with provider and result on success" do
      Amur.Controller.callback(callback_conn(), %{"provider" => "fake", "code" => "code"})

      assert_receive {:telemetry, [:amur, :callback, :start], _measurements, %{provider: :fake}}
      assert_receive {:telemetry, [:amur, :callback, :stop], measurements, metadata}

      assert is_integer(measurements.duration)
      assert metadata.provider == :fake
      assert metadata.result == :ok
      assert metadata.strategy == Amur.TelemetryTest.Strategy
    end

    test "emits a matching start and stop pair for invalid session params" do
      Amur.Controller.callback(callback_conn(%{}), %{"provider" => "fake"})

      assert_receive {:telemetry, [:amur, :callback, :start], _measurements, %{provider: :fake}}
      assert_receive {:telemetry, [:amur, :callback, :stop], _measurements, metadata}

      assert metadata.result == :error
      assert metadata.reason == :invalid_session_params
    end

    test "does not include the connection, session, token, or user in metadata" do
      Amur.Controller.callback(callback_conn(), %{"provider" => "fake", "code" => "code"})

      assert_receive {:telemetry, [:amur, :callback, :start], _measurements, start_metadata}
      assert_receive {:telemetry, [:amur, :callback, :stop], _measurements, stop_metadata}

      for metadata <- [start_metadata, stop_metadata] do
        refute Map.has_key?(metadata, :conn)
        refute Map.has_key?(metadata, :session)
        refute Map.has_key?(metadata, :token)
        refute Map.has_key?(metadata, :user)
      end
    end
  end

  describe "exception span" do
    test "emits an exception event and re-raises the original error" do
      Application.put_env(:amur, :providers, raising: Amur.TelemetryTest.RaisingProvider)

      assert_raise RuntimeError, "boom", fn ->
        Amur.Controller.request(Plug.Test.conn(:get, "/"), %{"provider" => "raising"})
      end

      assert_receive {:telemetry, [:amur, :request, :exception], measurements, metadata}

      assert is_integer(measurements.duration)
      assert metadata.provider == :raising
      assert metadata.kind == :error
      assert %RuntimeError{message: "boom"} = metadata.reason
      assert is_list(metadata.stacktrace)

      # `strategy` is only known once the provider has resolved, and an
      # exception can be raised before that, so it is never on `:exception`.
      refute Map.has_key?(metadata, :strategy)
    end

    test "emits a callback exception event and re-raises the original error" do
      Application.put_env(:amur, :providers, raising: Amur.TelemetryTest.RaisingProvider)

      assert_raise RuntimeError, "boom", fn ->
        Amur.Controller.callback(callback_conn(), %{"provider" => "raising", "code" => "code"})
      end

      assert_receive {:telemetry, [:amur, :callback, :exception], measurements, metadata}

      assert is_integer(measurements.duration)
      assert metadata.provider == :raising
      assert metadata.kind == :error
      assert %RuntimeError{message: "boom"} = metadata.reason
      assert is_list(metadata.stacktrace)
      refute Map.has_key?(metadata, :strategy)
    end

    test "does not leak secrets through the stacktrace" do
      Application.put_env(:amur, :providers, leaking: Amur.TelemetryTest.LeakingProvider)

      assert_raise FunctionClauseError, fn ->
        Amur.Controller.request(Plug.Test.conn(:get, "/"), %{"provider" => "leaking"})
      end

      assert_receive {:telemetry, [:amur, :request, :exception], _measurements, metadata}

      # The stacktrace must not carry the argument list, which holds the
      # provider config and its client_secret.
      refute inspect(metadata.stacktrace) =~ "super-secret-value"

      # Frames keep module, function, arity and location.
      assert Enum.all?(metadata.stacktrace, fn
               {module, function, arity, location} ->
                 is_atom(module) and is_atom(function) and is_integer(arity) and
                   is_list(location)

               _other ->
                 true
             end)
    end
  end

  describe "span boundary" do
    test "the failure callback runs outside the request span" do
      # The `:on_failure` callback is host application code, so its duration must
      # not be attributed to Amur. Assert the ordering structurally rather than
      # with a wall-clock threshold: the callback records the monotonic time at
      # which it ran, and that must be at or after the span's stop time.
      Application.put_env(:amur, :providers, [])

      test_pid = self()

      Application.put_env(:amur, :on_failure, fn conn, _reason ->
        send(test_pid, {:on_failure_ran_at, System.monotonic_time()})
        conn
      end)

      Amur.Controller.request(Plug.Test.conn(:get, "/"), %{"provider" => "missing"})

      assert_receive {:telemetry, [:amur, :request, :stop], measurements, metadata}
      assert metadata.result == :error

      assert_receive {:on_failure_ran_at, callback_time}

      assert callback_time >= measurements.monotonic_time,
             "on_failure ran inside the span (callback #{callback_time} < stop #{measurements.monotonic_time})"
    end

    test "an exception raised by the failure callback is not an Amur exception" do
      Application.put_env(:amur, :providers, [])
      Application.put_env(:amur, :on_failure, fn _conn, _reason -> raise "on_failure boom" end)

      assert_raise RuntimeError, "on_failure boom", fn ->
        Amur.Controller.request(Plug.Test.conn(:get, "/"), %{"provider" => "missing"})
      end

      # The request span completed normally; the callback's crash is not
      # reported as an `[:amur, :request, :exception]`.
      assert_receive {:telemetry, [:amur, :request, :stop], _measurements, %{result: :error}}
      refute_receive {:telemetry, [:amur, :request, :exception], _measurements, _metadata}
    end
  end

  describe "handler isolation" do
    import ExUnit.CaptureLog

    test "a raising handler does not break the flow" do
      :telemetry.detach(@handler_id)

      on_exit(fn -> :telemetry.detach("amur-telemetry-raising-test") end)

      # `:telemetry` logs the handler failure and detaches the handler. Capture
      # that log so the intentional error does not clutter the test output, and
      # assert it happened rather than printing it. The attach is inside the
      # capture too, since `:telemetry` logs a notice about local handlers.
      log =
        capture_log(fn ->
          :telemetry.attach(
            "amur-telemetry-raising-test",
            [:amur, :request, :stop],
            fn _event, _measurements, _metadata, _config -> raise "handler boom" end,
            nil
          )

          conn = Amur.Controller.request(start_conn(), %{"provider" => "fake"})

          assert conn.status == 302

          assert Plug.Conn.get_resp_header(conn, "location") == [
                   "https://provider.example/authorize"
                 ]
        end)

      assert log =~ "amur-telemetry-raising-test"
      assert log =~ "handler boom"
    end
  end

  describe "provider resolution" do
    test "an unknown provider request does not create atoms" do
      name = "amur_telemetry_definitely_not_an_existing_atom"

      Amur.Controller.request(Plug.Test.conn(:get, "/"), %{"provider" => name})

      assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
    end

    test "an existing but unconfigured atom is not used as a label" do
      # `:ok` is an existing atom, but it is not a configured provider, so it
      # must not appear as a metric label.
      Amur.Controller.request(Plug.Test.conn(:get, "/"), %{"provider" => "ok"})

      assert_receive {:telemetry, [:amur, :request, :start], _measurements, %{provider: nil}}
    end

    test "a configured provider that does not resolve is not used as a label" do
      # The name is a key in `:providers`, but its value is neither a module nor
      # credentials, so `Amur.Config.resolve/1` fails. The label must agree with
      # that outcome rather than reporting the configured atom.
      Application.put_env(:amur, :providers, weird: "not-a-module")

      Amur.Controller.request(Plug.Test.conn(:get, "/"), %{"provider" => "weird"})

      assert_receive {:telemetry, [:amur, :request, :start], _measurements, %{provider: nil}}
      assert_receive {:telemetry, [:amur, :request, :stop], _measurements, metadata}
      assert metadata.result == :error
      assert metadata.reason == :unknown_provider
    end

    test "a non-binary provider parameter is not used as a label" do
      # A malformed query such as `?provider[]=x` yields a list. It matches no
      # configured key, so the label is `nil` and the flow fails cleanly rather
      # than raising inside `Amur.Config.resolve/1`.
      Amur.Controller.request(Plug.Test.conn(:get, "/"), %{"provider" => ["fake"]})

      assert_receive {:telemetry, [:amur, :request, :start], _measurements, %{provider: nil}}
      assert_receive {:telemetry, [:amur, :request, :stop], _measurements, metadata}
      assert metadata.result == :error
      assert metadata.reason == :unknown_provider
    end

    test "an atom provider parameter is labelled with the resolved provider" do
      # `Amur.Config.resolve/1` accepts an atom as well as a binary, so the label
      # must agree with the outcome for both. Before the fix the comparison was
      # `to_string(name) == provider`, which is false for an atom and labelled a
      # successful request `nil`.
      conn = Amur.Controller.request(start_conn(), %{"provider" => :fake})

      assert conn.status == 302

      assert_receive {:telemetry, [:amur, :request, :start], _measurements, %{provider: :fake}}
      assert_receive {:telemetry, [:amur, :request, :stop], _measurements, metadata}
      assert metadata.provider == :fake
      assert metadata.result == :ok
    end

    test "a provider that raises while resolving is reported as an exception" do
      # Resolution runs before the span body, so a raising `base_config/0` must
      # not crash the request outside the span with no telemetry emitted.
      Application.put_env(:amur, :providers,
        raising_config: Amur.TelemetryTest.RaisingConfigProvider
      )

      assert_raise RuntimeError, "config boom", fn ->
        Amur.Controller.request(Plug.Test.conn(:get, "/"), %{"provider" => "raising_config"})
      end

      assert_receive {:telemetry, [:amur, :request, :exception], _measurements, metadata}
      assert metadata.provider == :raising_config
      assert %RuntimeError{message: "config boom"} = metadata.reason
    end
  end

  describe "sanitize_reason/1" do
    test "passes through Amur's own reasons" do
      assert Telemetry.sanitize_reason(:unknown_provider) == :unknown_provider
      assert Telemetry.sanitize_reason(:invalid_session_params) == :invalid_session_params
    end

    test "unwraps an {:error, reason} tuple" do
      assert Telemetry.sanitize_reason({:error, :unknown_provider}) == :unknown_provider
    end

    test "categorizes Assent error structs" do
      assert Telemetry.sanitize_reason(Assent.CallbackCSRFError.exception(key: "state")) ==
               :state_mismatch

      assert Telemetry.sanitize_reason(
               Assent.CallbackError.exception(message: "denied", error: "access_denied")
             ) == :access_denied

      assert Telemetry.sanitize_reason(Assent.CallbackError.exception(message: "other")) ==
               :provider_error
    end

    test "categorizes transport-level failures as network errors" do
      # Assent wraps every adapter failure in `ServerUnreachableError`, so this
      # is the shape Amur actually sees for a transport error, whatever the
      # underlying adapter (Mint, :httpc, ...) reported in `:reason`.
      assert Telemetry.sanitize_reason(
               Assent.ServerUnreachableError.exception(
                 http_adapter: Assent.HTTPAdapter.Httpc,
                 request_url: "https://example.com",
                 reason: :timeout
               )
             ) == :network_error

      assert Telemetry.sanitize_reason(
               Assent.ServerUnreachableError.exception(
                 http_adapter: Assent.HTTPAdapter.Httpc,
                 request_url: "https://example.com",
                 reason: %{__struct__: Mint.TransportError, reason: :closed}
               )
             ) == :network_error
    end

    test "falls back to :provider_error for unknown reasons" do
      assert Telemetry.sanitize_reason({:badmatch, "some response body"}) == :provider_error
      assert Telemetry.sanitize_reason(:something_else) == :provider_error
    end
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

  defmodule RaisingStrategy do
    def authorize_url(_config), do: raise("boom")
    def callback(_config, _params), do: raise("boom")
  end

  # Raises a FunctionClauseError whose arguments include the provider config, so
  # the test can prove the stacktrace is scrubbed of the secret it carries.
  defmodule LeakingStrategy do
    def authorize_url(config) do
      # No clause matches a keyword list, so this raises a FunctionClauseError
      # whose arguments are the config, including the client_secret.
      authorize_url(config, config)
    end

    def authorize_url(_config, secret) when is_binary(secret), do: :ok
  end

  defmodule Provider do
    use Amur.Provider
    def strategy, do: Amur.TelemetryTest.Strategy
    def base_config, do: []
    def normalize_user(user), do: %{uid: user["id"], email: user["email"]}
  end

  defmodule FailingProvider do
    use Amur.Provider
    def strategy, do: Amur.TelemetryTest.FailingStrategy
    def base_config, do: []
    def normalize_user(user), do: user
  end

  defmodule RaisingProvider do
    use Amur.Provider
    def strategy, do: Amur.TelemetryTest.RaisingStrategy
    def base_config, do: []
    def normalize_user(user), do: user
  end

  defmodule LeakingProvider do
    use Amur.Provider
    def strategy, do: Amur.TelemetryTest.LeakingStrategy
    def base_config, do: [client_secret: "super-secret-value"]
    def normalize_user(user), do: user
  end

  # Raises while building its config, which happens during provider resolution
  # before the span body runs. The request must still emit a span rather than
  # crash outside it with no telemetry.
  defmodule RaisingConfigProvider do
    use Amur.Provider
    def strategy, do: Amur.TelemetryTest.Strategy
    def base_config, do: raise("config boom")
    def normalize_user(user), do: user
  end
end

defmodule Amur.Controller do
  @moduledoc """
  Coordinates the provider-facing part of Amur's OAuth flow.

  `request/2` resolves a configured provider, builds its authorization URL,
  stores the provider-specific session parameters, and redirects the user to
  the provider. `callback/2` consumes that session state, exchanges the
  callback parameters for a token, normalizes the provider's user response,
  and invokes the configured `:on_success` callback.

  Both entry points use the configured `:on_failure` callback when a provider
  cannot be resolved, an OAuth operation fails, or the callback session state
  is invalid. The default failure handler redirects to `/`.

  The controller expects the surrounding Plug pipeline to fetch the session
  before calling these functions. `Amur.Router` performs that setup
  automatically.
  """

  import Plug.Conn

  @doc """
  Starts an OAuth authorization request for the provider in `params`.

  The provider's strategy supplies the authorization URL and any parameters
  that must survive until the callback, such as the OAuth `state` value.
  Those parameters are stored in the Plug session before the redirect.

  Returns a halted connection after redirecting to the provider, or the
  connection returned by the configured failure callback.
  """
  def request(conn, %{"provider" => provider}) do
    result =
      Amur.Telemetry.span([:amur, :request], %{provider: resolve_provider(provider)}, fn ->
        case do_request(conn, provider) do
          {:ok, conn, strategy} ->
            {{:ok, conn}, %{result: :ok, strategy: strategy}}

          {:error, reason, strategy} ->
            {{:error, reason}, stop_metadata(reason, strategy)}
        end
      end)

    case result do
      {:ok, conn} ->
        conn

      {:error, reason} ->
        handle_failure(conn, reason)
    end
  end

  defp do_request(conn, provider) do
    case Amur.Config.resolve(provider) do
      {:ok, {_module, config}} ->
        strategy = Keyword.fetch!(config, :strategy)

        case strategy.authorize_url(config) do
          {:ok, %{url: url, session_params: session_params}} ->
            conn =
              conn
              |> put_session(:amur_session_params, session_params)
              |> redirect(url)

            {:ok, conn, strategy}

          {:error, reason} ->
            {:error, reason, strategy}
        end

      {:error, reason} ->
        {:error, reason, nil}
    end
  end

  @doc """
  Completes an OAuth authorization request for the provider in `params`.

  The callback consumes and immediately removes the session parameters saved
  by `request/2`, validates that they contain a non-empty `state`, and passes
  them with the callback parameters to the provider strategy. On success, the
  provider user is normalized and sent to the configured `:on_success`
  callback together with the token.

  Returns the connection returned by the success or failure callback.
  """
  def callback(conn, %{"provider" => provider} = params) do
    session_params = get_session(conn, :amur_session_params)
    conn = delete_session(conn, :amur_session_params)

    result =
      Amur.Telemetry.span([:amur, :callback], %{provider: resolve_provider(provider)}, fn ->
        case do_callback(conn, provider, session_params, params) do
          {:ok, %{user: user, token: token}, strategy} ->
            {{:ok, user, token}, %{result: :ok, strategy: strategy}}

          {:error, reason, strategy} ->
            {{:error, reason}, stop_metadata(reason, strategy)}
        end
      end)

    case result do
      {:ok, user, token} ->
        on_success = Application.fetch_env!(:amur, :on_success)
        on_success.(conn, %{user: user, token: token})

      {:error, reason} ->
        handle_failure(conn, reason)
    end
  end

  defp do_callback(_conn, provider, session_params, params) do
    case Amur.Config.resolve(provider) do
      {:ok, {module, config}} ->
        strategy = Keyword.fetch!(config, :strategy)
        config = Keyword.put(config, :session_params, session_params)

        with :ok <- validate_session_params(session_params),
             {:ok, %{user: user, token: token}} <- strategy.callback(config, params) do
          normalized =
            user
            |> module.normalize_user()
            |> Map.put(:provider, provider)

          {:ok, %{user: normalized, token: token}, strategy}
        else
          {:error, reason} -> {:error, reason, strategy}
        end

      {:error, reason} ->
        {:error, reason, nil}
    end
  end

  # Builds the `:stop` metadata. `strategy` is included only when the provider
  # resolved far enough to know it, so a handler can rely on the key being
  # present whenever the failure came from the strategy rather than from
  # resolving the provider itself. The check is `is_nil/1` rather than
  # truthiness: a strategy is a module atom, and relying on truthiness is the
  # same trap that made a provider named `false` unlabelled in
  # `resolve_provider/1`.
  defp stop_metadata(reason, strategy) do
    metadata = %{result: :error, reason: Amur.Telemetry.sanitize_reason(reason)}
    if is_nil(strategy), do: metadata, else: Map.put(metadata, :strategy, strategy)
  end

  # Resolves the provider name for telemetry metadata without touching the atom
  # table. The request parameter is matched against the configured provider keys
  # rather than converted with `String.to_existing_atom/1`, so a path like
  # `/auth/ok` cannot label a metric with an unrelated existing atom. A name that
  # is configured but does not resolve (for example a provider whose value is not
  # a module or credentials) reports `nil`, so the label always agrees with the
  # outcome of `Amur.Config.resolve/1` and metric labels stay bounded.
  #
  # The parameter may be a binary (the router passes the URL segment) or an atom
  # (`Amur.Config.resolve/1` accepts both), so both are normalized before the
  # comparison; otherwise an atom parameter would resolve successfully but be
  # labelled `nil`.
  #
  # This runs before the span opens, so it must not call provider code:
  # `Amur.Config.resolvable?/1` answers the same question as `resolve/1` from the
  # shape of the configured value alone. The actual resolution happens inside the
  # span body, so a provider whose `base_config/0` raises is reported as an
  # `:exception` event rather than crashing the request with no telemetry.
  defp resolve_provider(provider) when is_binary(provider) or is_atom(provider) do
    configured = Application.get_env(:amur, :providers, [])
    wanted = to_string(provider)

    # `Enum.find_value/3` would treat a provider named `false` (or `nil`) as "not
    # found", because it stops on any falsy return. `Enum.find/2` compares the
    # match explicitly, so the label agrees with `Amur.Config.resolve/1` for
    # every configured name.
    case Enum.find(configured, fn {name, _value} ->
           to_string(name) == wanted and Amur.Config.resolvable?(name)
         end) do
      {name, _value} -> name
      nil -> nil
    end
  end

  # A malformed parameter (for example `?provider[]=x`, which Plug parses as a
  # list) is not a provider name, so it cannot label a metric.
  defp resolve_provider(_provider), do: nil

  # Delegate failure handling to application code when a custom callback is
  # configured; otherwise use the default redirect handler.
  defp handle_failure(conn, reason) do
    on_failure = Application.get_env(:amur, :on_failure, &Amur.Controller.default_failure/2)
    on_failure.(conn, reason)
  end

  # Assent strategies may return either a map or keyword list, so accept both
  # shapes while requiring a usable state value in either case.
  defp validate_session_params(%{state: state}) when is_binary(state) and state != "" do
    :ok
  end

  defp validate_session_params(session_params) when is_list(session_params) do
    if Keyword.get(session_params, :state) in [nil, ""] do
      {:error, :invalid_session_params}
    else
      :ok
    end
  end

  defp validate_session_params(_session_params), do: {:error, :invalid_session_params}

  @doc """
  Handles an OAuth failure when no custom `:on_failure` callback is configured.

  The default behavior redirects the user to the application root.
  """
  def default_failure(conn, _reason) do
    conn
    |> redirect("/")
  end

  # OAuth redirects must halt the Plug pipeline so later plugs do not modify
  # the response or attempt to send a second one.
  defp redirect(conn, to) do
    conn
    |> put_resp_header("location", to)
    |> send_resp(302, "")
    |> halt()
  end
end

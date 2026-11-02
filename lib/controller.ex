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

  alias Assent.Strategy.Telegram
  alias Plug.Conn.Query

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

        case authorize_url(strategy, config) do
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

  # Telegram signs user data rather than returning OAuth session params. Bind
  # its return URL to this browser session before asking Assent for the URL.
  defp authorize_url(Telegram, config) do
    with {:ok, return_to} <- Assent.fetch_config(config, :return_to) do
      state = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
      uri = URI.parse(return_to)

      query =
        URI.decode_query(uri.query || "") |> Map.put("amur_state", state) |> URI.encode_query()

      config = Keyword.put(config, :return_to, URI.to_string(%{uri | query: query}))

      with {:ok, %{url: url}} <- Telegram.authorize_url(config) do
        {:ok, %{url: url, session_params: %{state: state}}}
      end
    end
  end

  defp authorize_url(strategy, config), do: strategy.authorize_url(config)

  @doc """
  Completes an OAuth authorization request for the provider in `params`.

  The callback consumes and immediately removes the session parameters saved
  by `request/2`, validates the required handshake value (`state` for OAuth 2.0,
  or the request token secret for OAuth 1.0), and passes them with the callback
  parameters to the provider strategy. On success, the provider user is
  normalized and sent to the configured `:on_success`
  callback together with the token (`nil` for Telegram's signed login data).

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
        invoke_callback(on_success, conn, %{user: user, token: token})

      {:error, reason} ->
        handle_failure(conn, reason)
    end
  end

  defp do_callback(_conn, provider, session_params, params) do
    case Amur.Config.resolve(provider) do
      {:ok, {module, config}} ->
        strategy = Keyword.fetch!(config, :strategy)
        normalized_params = normalize_session_params(session_params)

        config =
          Keyword.put(config, :session_params, strategy_session_params(session_params, strategy))

        with :ok <- validate_session_params(normalized_params, strategy),
             {:ok, %{user: user, token: token}} <- strategy_callback(strategy, config, params) do
          normalized =
            user
            |> module.normalize_user()
            |> Map.put(:provider, to_string(provider))

          {:ok, %{user: normalized, token: token}, strategy}
        else
          {:error, reason} -> {:error, reason, strategy}
        end

      {:error, reason} ->
        {:error, reason, nil}
    end
  end

  defp strategy_callback(Telegram, config, params) do
    session_params = Keyword.fetch!(config, :session_params)
    provided_state = params["amur_state"]

    if is_binary(provided_state) and
         Assent.constant_time_compare(session_params.state, provided_state) do
      # The routing key and return URL's own query params are not part of
      # Telegram's signed payload, so they must not be included in its HMAC.
      return_to = URI.parse(Keyword.fetch!(config, :return_to))
      return_keys = Query.decode(return_to.query || "") |> Map.keys()
      params = Map.drop(params, ["provider", "amur_state" | return_keys])

      with :ok <- validate_telegram_params(config, params),
           {:ok, %{user: user}} <- Telegram.callback(config, params) do
        {:ok, %{user: user, token: nil}}
      end
    else
      {:error, Assent.CallbackCSRFError.exception(key: "amur_state")}
    end
  end

  defp strategy_callback(strategy, config, params) do
    with :ok <- validate_assent_params(strategy, params),
         {:ok, params} <- prepare_callback_params(strategy, config, params) do
      strategy.callback(config, params)
    end
  end

  defp prepare_callback_params(Assent.Strategy.Apple, config, %{"user" => data} = params) do
    # Only Apple's first-login name belongs in this unsigned form field;
    # identity claims must stay signed, including with older Assent versions.
    with {:ok, user} <- Assent.Strategy.decode_json(data, config),
         true <- is_map(user) and valid_apple_name?(user) do
      data = Assent.json_library(config).encode!(Map.take(user, ["name"]))
      {:ok, Map.put(params, "user", data)}
    else
      _ -> malformed_callback("Malformed Apple user data")
    end
  end

  defp prepare_callback_params(_strategy, _config, params), do: {:ok, params}

  defp valid_apple_name?(%{"name" => name}) when is_map(name) do
    Enum.all?(~w(firstName lastName), fn key ->
      is_nil(name[key]) or is_binary(name[key])
    end)
  end

  defp valid_apple_name?(user), do: not Map.has_key?(user, "name")

  defp validate_telegram_params(config, params) do
    case Keyword.get(config, :authorization_channel, :login_widget) do
      :login_widget ->
        validate_telegram_login_params(params)

      :web_mini_app ->
        case Map.fetch(params, "init_data") do
          {:ok, data} when is_binary(data) ->
            data |> URI.decode_query() |> validate_telegram_login_params()

          {:ok, _data} ->
            malformed_callback("Malformed Telegram login data")

          :error ->
            :ok
        end

      _channel ->
        :ok
    end
  end

  defp validate_telegram_login_params(params) do
    scalar_values? =
      Enum.all?(params, fn {_key, value} ->
        is_binary(value) or is_integer(value) or is_boolean(value)
      end)

    hash_valid? = not Map.has_key?(params, "hash") or is_binary(params["hash"])
    date_valid? = not Map.has_key?(params, "auth_date") or valid_timestamp?(params["auth_date"])

    if scalar_values? and hash_valid? and date_valid?,
      do: :ok,
      else: malformed_callback("Malformed Telegram login data")
  end

  defp valid_timestamp?(value) when is_integer(value), do: true

  defp valid_timestamp?(value) when is_binary(value) and byte_size(value) <= 20 do
    match?({_integer, ""}, Integer.parse(value))
  end

  defp valid_timestamp?(_value), do: false

  defp validate_assent_params(strategy, params) do
    known_strategy? =
      strategy in [Assent.Strategy.OAuth, Assent.Strategy.OAuth2, Assent.Strategy.OIDC] or
        Enum.any?(strategy_behaviours(strategy), fn behaviour ->
          behaviour in [
            Assent.Strategy.OAuth.Base,
            Assent.Strategy.OAuth2.Base,
            Assent.Strategy.OIDC.Base
          ]
        end)

    if known_strategy? do
      fields =
        ~w(state code error error_description error_reason error_uri oauth_token oauth_verifier denied)

      fields = if strategy == Assent.Strategy.Apple, do: ["user" | fields], else: fields

      case Enum.find(fields, &(Map.has_key?(params, &1) and not is_binary(params[&1]))) do
        nil -> :ok
        "state" -> {:error, Assent.CallbackCSRFError.exception(key: "state")}
        _field -> malformed_callback("Malformed OAuth callback parameters")
      end
    else
      :ok
    end
  end

  defp malformed_callback(message), do: {:error, Assent.CallbackError.exception(message: message)}

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
    invoke_callback(on_failure, conn, reason)
  end

  defp invoke_callback({module, function, args}, conn, payload) do
    apply(module, function, [conn, payload | args])
  end

  defp invoke_callback(callback, conn, payload), do: callback.(conn, payload)

  # Validate keyword sessions like maps, while retaining custom strategies'
  # original session representation when passing it back to their callback.
  defp normalize_session_params(session_params) when is_list(session_params) do
    if Keyword.keyword?(session_params), do: Map.new(session_params), else: session_params
  end

  defp normalize_session_params(session_params), do: session_params

  defp strategy_session_params(session_params, strategy) do
    uses_map? =
      strategy in [Assent.Strategy.OAuth2, Assent.Strategy.OIDC, Telegram] or
        Enum.any?(strategy_behaviours(strategy), fn behaviour ->
          behaviour in [Assent.Strategy.OAuth2.Base, Assent.Strategy.OIDC.Base]
        end)

    if uses_map?, do: normalize_session_params(session_params), else: session_params
  end

  # OAuth 1.0 binds the callback with the request token secret instead of state.
  defp validate_session_params(session_params, strategy) do
    oauth1? =
      strategy == Assent.Strategy.OAuth or
        Assent.Strategy.OAuth.Base in strategy_behaviours(strategy)

    key = if oauth1?, do: :oauth_token_secret, else: :state
    validate_session_param(session_params, key)
  end

  # Inspect persisted behaviour metadata inside the span, after resolution.
  # This also handles custom strategies built on Assent's strategy bases.
  defp strategy_behaviours(strategy) do
    case Code.ensure_loaded(strategy) do
      {:module, _module} ->
        strategy.module_info(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()

      {:error, _reason} ->
        []
    end
  end

  defp validate_session_param(session_params, key) when is_map(session_params) do
    case Map.get(session_params, key) do
      value when is_binary(value) and value != "" -> :ok
      _value -> {:error, :invalid_session_params}
    end
  end

  defp validate_session_param(_session_params, _key), do: {:error, :invalid_session_params}

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

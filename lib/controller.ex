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
    with {:ok, {_module, config}} <- Amur.Config.resolve(provider),
         strategy = Keyword.fetch!(config, :strategy),
         {:ok, %{url: url, session_params: session_params}} <- strategy.authorize_url(config) do
      conn
      |> put_session(:amur_session_params, session_params)
      |> redirect(url)
    else
      {:error, reason} -> handle_failure(conn, reason)
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

    with {:ok, {module, config}} <- Amur.Config.resolve(provider),
         strategy = Keyword.fetch!(config, :strategy),
         config = Keyword.put(config, :session_params, session_params),
         :ok <- validate_session_params(session_params),
         {:ok, %{user: user, token: token}} <- strategy.callback(config, params) do
      normalized =
        user
        |> module.normalize_user()
        |> Map.put(:provider, provider)

      on_success = Application.fetch_env!(:amur, :on_success)
      on_success.(conn, %{user: normalized, token: token})
    else
      {:error, reason} -> handle_failure(conn, reason)
    end
  end

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

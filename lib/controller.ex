defmodule Amur.Controller do
  import Plug.Conn

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

  defp handle_failure(conn, reason) do
    on_failure = Application.get_env(:amur, :on_failure, &Amur.Controller.default_failure/2)
    on_failure.(conn, reason)
  end

  defp validate_session_params(%{state: state}) when is_binary(state) and state != "" do
    :ok
  end

  defp validate_session_params(session_params) when is_list(session_params) do
    if Keyword.get(session_params, :state) not in [nil, ""] do
      :ok
    else
      {:error, :invalid_session_params}
    end
  end

  defp validate_session_params(_session_params), do: {:error, :invalid_session_params}

  def default_failure(conn, _reason) do
    conn
    |> redirect("/")
  end

  defp redirect(conn, to) do
    conn
    |> put_resp_header("location", to)
    |> send_resp(302, "")
    |> halt()
  end
end

defmodule Amur do
  @moduledoc """
  Simple OAuth for Plug apps.

  ## Setup

  ```elixir

  # mix.exs
  {:amur, "~> 0.1"}

  # config/runtime.exs
  config :amur,
    providers: [
      github: [
        client_id: System.fetch_env!("GITHUB_CLIENT_ID"),
        client_secret: System.fetch_env!("GITHUB_CLIENT_SECRET")
      ]
    ],
    on_success: &MyApp.Accounts.find_or_create/3,
    on_failure: &MyApp.Accounts.auth_failed/2

  # router.ex
  forward "/auth", Amur.Router
  ```

  Mount `Amur.Router` under `/auth` in your router with `forward "/auth", Amur.Router`.
  In Phoenix, place the forward inside your browser pipeline so session and
  flash helpers are available if your callbacks use them, and use `alias: false`
  on the scope that contains the forward so Phoenix does not rewrite the module
  name. It works with both `Phoenix.Router` and `Plug.Router`. It exposes:

  - `GET /auth/:provider` to start the OAuth flow
  - `GET /auth/:provider/callback` to handle the callback
  - `GET /auth/logout` to clear Amur's stored session params

  The helper below only clears Amur's stored OAuth session params.
  """
  def logout(conn) do
    conn
    |> Plug.Conn.delete_session(:amur_session_params)
  end
end

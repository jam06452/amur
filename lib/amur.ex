defmodule Amur do
  @moduledoc """
  Simple OAuth for Plug apps.

  ## Setup

  ```elixir
  # mix.exs
  {:amur, "~> 0.2"}

  # config/runtime.exs
  config :amur,
    base_url: "http://localhost:4000",
    providers: [
      github: [
        client_id: System.fetch_env!("GITHUB_CLIENT_ID"),
        client_secret: System.fetch_env!("GITHUB_CLIENT_SECRET")
      ]
    ],
    on_success: &MyAppWeb.AuthController.on_success/2,
    on_failure: &MyAppWeb.AuthController.on_failure/2

  # router.ex
  forward "/auth", Amur.Router
  ```

  Mount `Amur.Router` under `/auth` in your router with `forward "/auth", Amur.Router`.
  In Phoenix, place the forward inside your browser pipeline so session and
  flash helpers are available if your callbacks use them, and use `alias: false`
  on the scope that contains the forward so Phoenix does not rewrite the module
  name. It works with both `Phoenix.Router` and `Plug.Router`. It exposes:

  - `GET /auth/:provider` - start the OAuth flow
  - `GET /auth/:provider/callback`- handle the provider callback
  - `GET /auth/logout` - clear Amur's stored session params

  ## Logout helper

  `Amur.logout/1` clears Amur's stored OAuth session params from the conn.
  Use it in your own logout handler, or rely on the built-in `GET /auth/logout` endpoint.
  """
  def logout(conn) do
    conn
    |> Plug.Conn.delete_session(:amur_session_params)
  end
end

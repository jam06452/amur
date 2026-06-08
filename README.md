# Amur
Simple OAuth for Plug apps.
Amur gives you a small OAuth callback flow and provider normalization layer.
It is Plug-based and does not require Phoenix.

## Installation
If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `amur` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:amur, "~> 0.1.1"}
  ]
end
```

## Setup

1. Add the dependency and configure your provider credentials.

```elixir
config :amur,
  base_url: "http://localhost:4000",
  providers: [
    github: [
      client_id: System.fetch_env!("GITHUB_CLIENT_ID"),
      client_secret: System.fetch_env!("GITHUB_CLIENT_SECRET")
    ]
  ],
  on_success: &MyApp.AuthController.on_success/2,
  on_failure: &MyApp.AuthController.on_failure/2
```

2. Mount the router in your application router.

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  scope "/auth", alias: false do
    pipe_through :browser
    forward "/", Amur.Router
  end
end
```

`forward "/", Amur.Router` inside a `/auth` scope mounts the auth endpoints under `/auth`:
- `GET /auth/:provider` — starts the OAuth flow.
- `GET /auth/:provider/callback` — handles the provider callback.
- `GET /auth/logout` — clears Amur's stored session params.

If you want a different base path, change the scope path. Keep the forward inside a pipeline
that runs `fetch_session` and `fetch_flash` if your callbacks use session or flash helpers.
The `alias: false` on the scope is required, otherwise Phoenix will rewrite it as
`YourAppWeb.Amur.Router`.

3. Add an Auth Controller to handle the results of the authentication process.

```elixir
defmodule MyApp.AuthController do
  import Plug.Conn
  import Phoenix.Controller

  def on_success(conn, user) do
    IO.inspect(user, label: "AUTH SUCCESS - #{user.provider}")
    conn
    |> put_flash(:info, "Logged in as #{user.email}")
    |> put_resp_header("location", "/")
    |> send_resp(302, "Redirecting...")
    |> halt()
  end

  def on_failure(conn, reason) do
    IO.inspect(reason, label: "AUTH FAILURE")
    conn
    |> put_flash(:error, "Authentication Error")
    |> put_resp_header("location", "/")
    |> send_resp(302, "Redirecting...")
    |> halt()
  end
end
```

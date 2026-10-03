defmodule Amur.PageTest do
  use ExUnit.Case, async: false

  setup do
    previous = %{
      providers: Application.get_env(:amur, :providers),
      app_name: Application.get_env(:amur, :app_name),
      logo: Application.get_env(:amur, :logo)
    }

    on_exit(fn ->
      for {key, value} <- previous do
        if is_nil(value),
          do: Application.delete_env(:amur, key),
          else: Application.put_env(:amur, key, value)
      end
    end)

    :ok
  end

  # Simulates a request forwarded by a host router mounted at `/auth`, which is
  # how Plug presents the request to `Amur.Router` in practice.
  defp render_page(script_name \\ ["auth"]) do
    conn =
      Plug.Test.conn(:get, "/auth")
      |> Plug.Test.init_test_session(%{})
      |> Map.put(:script_name, script_name)

    Amur.Router.call(%{conn | path_info: []}, [])
  end

  # The logo element, isolated from the provider buttons that also carry icons.
  defp logo_markup(body) do
    body
    |> String.split("\n")
    |> Enum.find(&String.contains?(&1, "amur-logo"))
    |> String.trim()
  end

  defp write_logo_file!(markup) do
    path = Path.join(System.tmp_dir!(), "amur_logo_#{System.unique_integer([:positive])}.svg")
    File.write!(path, markup)
    on_exit(fn -> File.rm(path) end)
    path
  end

  test "renders a link and icon for every configured provider" do
    Application.put_env(:amur, :app_name, "Acme")
    Application.put_env(:amur, :providers, github: [], google: [], discord: [])

    conn = render_page()

    assert conn.status == 200
    assert Plug.Conn.get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]

    for provider <- ["github", "google", "discord"] do
      assert conn.resp_body =~ ~s|href="/auth/#{provider}"|
      assert conn.resp_body =~ ~s|src="/auth/#{provider}.svg"|
    end

    assert conn.resp_body =~ "Sign in to Acme"
  end

  test "builds asset and provider URLs from the mount point" do
    Application.put_env(:amur, :providers, github: [])

    body = render_page(["auth"]).resp_body

    assert body =~ ~s|href="/auth/amur.css"|
    assert body =~ ~s|src="/auth/github.svg"|
    assert body =~ ~s|href="/auth/github"|
  end

  test "supports a router mounted at the root" do
    Application.put_env(:amur, :providers, github: [])

    body = render_page([]).resp_body

    assert body =~ ~s|href="/amur.css"|
    assert body =~ ~s|src="/github.svg"|
    assert body =~ ~s|href="/github"|
  end

  test "supports a router mounted at a nested prefix" do
    Application.put_env(:amur, :providers, github: [])

    body = render_page(["api", "v1", "auth"]).resp_body

    assert body =~ ~s|href="/api/v1/auth/amur.css"|
    assert body =~ ~s|src="/api/v1/auth/github.svg"|
    assert body =~ ~s|href="/api/v1/auth/github"|
  end

  test "uses the list layout for two or fewer providers" do
    Application.put_env(:amur, :providers, github: [], google: [])

    body = render_page().resp_body

    assert body =~ "amur-providers--list"
    refute body =~ "amur-providers--grid"
  end

  test "uses the grid layout for three or more providers" do
    Application.put_env(:amur, :providers, github: [], google: [], discord: [])

    body = render_page().resp_body

    assert body =~ "amur-providers--grid"
    refute body =~ "amur-providers--list"
  end

  test "falls back to a neutral heading when no app name is configured" do
    Application.delete_env(:amur, :app_name)
    Application.put_env(:amur, :providers, github: [])

    assert render_page().resp_body =~ "Sign in to your account"
  end

  test "responds with 404 when no providers are configured" do
    Application.put_env(:amur, :providers, [])

    conn = render_page()

    assert conn.status == 404
    assert conn.resp_body =~ "No Amur providers are configured."
  end

  test "ignores configured providers that do not resolve" do
    Application.put_env(:amur, :providers, github: [], nope: [])

    body = render_page().resp_body

    assert body =~ ~s|href="/auth/github"|
    refute body =~ ~s|href="/auth/nope"|
  end

  test "serves the stylesheet with the correct content type" do
    conn =
      Plug.Test.conn(:get, "/auth/amur.css")
      |> Plug.Test.init_test_session(%{})
      |> then(&Amur.Router.call(%{&1 | path_info: ["amur.css"]}, []))

    assert conn.status == 200
    assert Plug.Conn.get_resp_header(conn, "content-type") == ["text/css; charset=utf-8"]
    assert conn.resp_body =~ ".amur-page"
  end

  test "serves provider icons with the correct content type" do
    conn =
      Plug.Test.conn(:get, "/auth/github.svg")
      |> Plug.Test.init_test_session(%{})
      |> then(&Amur.Router.call(%{&1 | path_info: ["github.svg"]}, []))

    assert conn.status == 200
    assert Plug.Conn.get_resp_header(conn, "content-type") == ["image/svg+xml; charset=utf-8"]
    assert conn.resp_body =~ "<svg"
  end

  test "does not serve assets outside the static directory" do
    conn =
      Plug.Test.conn(:get, "/auth/../mix.exs")
      |> Plug.Test.init_test_session(%{})
      |> then(&Amur.Router.call(%{&1 | path_info: ["..", "mix.exs"]}, []))

    assert conn.status == nil
  end

  test "returns nil for an unknown asset so the caller can fall through" do
    conn = Plug.Test.conn(:get, "/auth/missing.svg")

    assert Amur.Page.asset(conn, ["missing.svg"]) == nil
  end

  test "compiles the template into the module instead of evaluating it per request" do
    # The template is compiled by `EEx.function_from_file/5`, so the module
    # exports no runtime EEx evaluation and the template is an external
    # resource that triggers a rebuild when it changes.
    refute function_exported?(Amur.Page, :render_page, 4)

    {:ok, {_module, [compile_info: info]}} =
      :beam_lib.chunks(:code.which(Amur.Page), [:compile_info])

    assert to_string(info[:source]) =~ "page.ex"
  end

  test "reflects a newly configured provider without recompiling Amur" do
    Application.put_env(:amur, :providers, github: [])
    refute render_page().resp_body =~ ~s|href="/auth/discord"|

    Application.put_env(:amur, :providers, github: [], discord: [])
    assert render_page().resp_body =~ ~s|href="/auth/discord"|
  end

  test "falls back to a provider icon when no logo is configured" do
    Application.delete_env(:amur, :logo)
    Application.put_env(:amur, :providers, github: [], google: [])

    assert logo_markup(render_page().resp_body) =~ ~s|src="/auth/github.svg"|
  end

  test "uses a configured logo path" do
    Application.put_env(:amur, :logo, {:path, "/images/logo.svg"})
    Application.put_env(:amur, :providers, github: [])

    assert logo_markup(render_page().resp_body) =~ ~s|src="/images/logo.svg"|
  end

  test "accepts a bare string as a logo path" do
    Application.put_env(:amur, :logo, "/brand.svg")
    Application.put_env(:amur, :providers, github: [])

    assert logo_markup(render_page().resp_body) =~ ~s|src="/brand.svg"|
  end

  test "inlines a logo from a local file" do
    path = write_logo_file!(~s|<svg viewBox="0 0 24 24"><rect width="24" height="24"/></svg>|)
    Application.put_env(:amur, :logo, {:file, path})
    Application.put_env(:amur, :providers, github: [])

    assert logo_markup(render_page().resp_body) =~ ~s|<rect width="24" height="24"/>|
  end

  test "treats a bare string pointing at a local file as a file" do
    path = write_logo_file!(~s|<svg viewBox="0 0 8 8"><circle cx="4" cy="4" r="4"/></svg>|)
    Application.put_env(:amur, :logo, path)
    Application.put_env(:amur, :providers, github: [])

    assert logo_markup(render_page().resp_body) =~ ~s|<circle cx="4" cy="4" r="4"/>|
  end

  test "falls back to a provider icon when the logo file is missing" do
    Application.put_env(:amur, :logo, {:file, "/nonexistent/logo.svg"})
    Application.put_env(:amur, :providers, github: [])

    assert logo_markup(render_page().resp_body) =~ ~s|src="/auth/github.svg"|
  end

  test "renders an inline SVG logo as markup" do
    markup = ~s|<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/></svg>|
    Application.put_env(:amur, :logo, {:svg, markup})
    Application.put_env(:amur, :providers, github: [])

    assert logo_markup(render_page().resp_body) =~ markup
  end

  test "ignores an invalid logo value and falls back to a provider icon" do
    Application.put_env(:amur, :logo, :not_a_logo)
    Application.put_env(:amur, :providers, github: [])

    assert logo_markup(render_page().resp_body) =~ ~s|src="/auth/github.svg"|
  end
end

defmodule Amur.PageTest do
  use ExUnit.Case, async: false

  defmodule CustomProvider do
    use Amur.Provider

    @impl true
    def strategy, do: Assent.Strategy.OAuth2

    @impl true
    def base_config, do: []

    @impl true
    def normalize_user(user), do: %{uid: user["id"]}
  end

  defmodule LogoProvider do
    use Amur.Provider

    @impl true
    def strategy, do: Assent.Strategy.OAuth2

    @impl true
    def base_config, do: []

    @impl true
    def normalize_user(user), do: %{uid: user["id"]}

    @impl true
    def logo, do: {:svg, ~s|<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/></svg>|}
  end

  defmodule PathLogoProvider do
    use Amur.Provider

    @impl true
    def strategy, do: Assent.Strategy.OAuth2

    @impl true
    def base_config, do: []

    @impl true
    def normalize_user(user), do: %{uid: user["id"]}

    @impl true
    def logo, do: {:path, "/images/custom.svg"}
  end

  defmodule InlineSvgProvider do
    use Amur.Provider

    @impl true
    def strategy, do: Assent.Strategy.OAuth2

    @impl true
    def base_config, do: []

    @impl true
    def normalize_user(user), do: %{uid: user["id"]}

    @impl true
    def logo do
      {:svg,
       """
       <?xml version="1.0" encoding="UTF-8"?>
       <!-- a comment -->
       <svg width="24" height="24" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/></svg>
       """}
    end
  end

  defmodule NoRootSvgProvider do
    use Amur.Provider

    @impl true
    def strategy, do: Assent.Strategy.OAuth2

    @impl true
    def base_config, do: []

    @impl true
    def normalize_user(user), do: %{uid: user["id"]}

    @impl true
    def logo, do: {:svg, "<circle cx=\"12\" cy=\"12\" r=\"10\"/>"}
  end

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
  # The markup spans multiple lines, so the whole element is captured.
  defp logo_markup(body) do
    case Regex.run(~r/<span class="amur-logo".*?<\/span>|<img class="amur-logo"[^>]*\/>/s, body) do
      [markup] -> markup
      nil -> ""
    end
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
    end

    # Icons are inlined so they can follow the page's text colour: one per
    # provider plus the logo fallback.
    assert length(Regex.scan(~r/<svg/, conn.resp_body)) == 4
    assert conn.resp_body =~ "Sign in to Acme"
  end

  test "inlines provider icons with currentColor so they adapt to dark mode" do
    Application.put_env(:amur, :providers, github: [])

    body = render_page().resp_body

    assert body =~ ~s|fill="currentColor"|
    refute body =~ ~s|fill="#000000"|
    refute body =~ "<img"
  end

  test "formats provider names for the button label" do
    Application.put_env(:amur, :providers, azure_ad: [], digital_ocean: [], github: [], line: [])

    body = render_page().resp_body

    assert body =~ "Continue with Azure AD"
    assert body =~ "Continue with DigitalOcean"
    assert body =~ "Continue with GitHub"
    assert body =~ "Continue with LINE"
    refute body =~ "Azure_ad"
    refute body =~ "Digital_ocean"
  end

  test "title-cases providers that are not in the label table" do
    Application.put_env(:amur, :providers, custom_thing: Amur.PageTest.CustomProvider)

    assert render_page().resp_body =~ "Continue with Custom Thing"
  end

  test "builds asset and provider URLs from the mount point" do
    Application.put_env(:amur, :providers, github: [])

    body = render_page(["auth"]).resp_body

    assert body =~ ~s|href="/auth/amur.css"|
    assert body =~ ~s|href="/auth/github"|
  end

  test "supports a router mounted at the root" do
    Application.put_env(:amur, :providers, github: [])

    body = render_page([]).resp_body

    assert body =~ ~s|href="/amur.css"|
    assert body =~ ~s|href="/github"|
  end

  test "supports a router mounted at a nested prefix" do
    Application.put_env(:amur, :providers, github: [])

    body = render_page(["api", "v1", "auth"]).resp_body

    assert body =~ ~s|href="/api/v1/auth/amur.css"|
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

  test "resets the document box so the page fills the viewport" do
    conn =
      Plug.Test.conn(:get, "/auth/amur.css")
      |> Plug.Test.init_test_session(%{})
      |> then(&Amur.Router.call(%{&1 | path_info: ["amur.css"]}, []))

    # Without this the browser's default body margin leaves a white border
    # around the page, which is visible against the dark background.
    assert conn.resp_body =~ ~r/html,\s*body\s*\{[^}]*margin:\s*0/
    assert conn.resp_body =~ ~r/html,\s*body\s*\{[^}]*background:\s*var\(--amur-bg\)/
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

    # Under `mix test --cover` the module is loaded from `cover_compiled.beam`,
    # which carries no compile info, so the source check only runs on a normal
    # build.
    case :code.which(Amur.Page) do
      path when is_list(path) ->
        if Path.basename(path) == "cover_compiled.beam" do
          assert true
        else
          {:ok, {_module, [compile_info: info]}} = :beam_lib.chunks(path, [:compile_info])
          assert to_string(info[:source]) =~ "page.ex"
        end

      _ ->
        assert true
    end
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

    markup = logo_markup(render_page().resp_body)

    assert markup =~ "<svg"
    assert markup =~ ~s|fill="currentColor"|
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

    assert logo_markup(render_page().resp_body) =~ "<svg"
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

    assert logo_markup(render_page().resp_body) =~ "<svg"
  end

  test "renders a custom provider's inline SVG logo on its button" do
    Application.delete_env(:amur, :logo)
    Application.put_env(:amur, :providers, custom: Amur.PageTest.LogoProvider)

    body = render_page().resp_body

    assert body =~ ~s|<circle cx="12" cy="12" r="10"/>|
  end

  test "renders a custom provider's logo path as an image on its button" do
    Application.delete_env(:amur, :logo)
    Application.put_env(:amur, :providers, custom: Amur.PageTest.PathLogoProvider)

    body = render_page().resp_body

    assert body =~ ~s|<img src="/images/custom.svg" alt="" />|
  end

  test "uses a custom provider's logo as the page logo fallback" do
    Application.delete_env(:amur, :logo)
    Application.put_env(:amur, :providers, custom: Amur.PageTest.LogoProvider)

    assert logo_markup(render_page().resp_body) =~ ~s|<circle cx="12" cy="12" r="10"/>|
  end

  test "preserves a path-based provider logo as the page logo fallback" do
    Application.delete_env(:amur, :logo)
    Application.put_env(:amur, :providers, custom: Amur.PageTest.PathLogoProvider)

    markup = logo_markup(render_page().resp_body)

    assert markup =~ ~s|<img class="amur-logo" src="/images/custom.svg"|
    refute markup =~ "<span class=\"amur-logo\""
  end

  test "renders no icon for a custom provider without a logo" do
    Application.delete_env(:amur, :logo)
    Application.put_env(:amur, :providers, custom: Amur.PageTest.CustomProvider)

    body = render_page().resp_body

    assert body =~ ~s|href="/auth/custom"|
    refute body =~ "<img"
  end

  test "prefers the page logo over a custom provider's logo" do
    Application.put_env(:amur, :logo, {:path, "/images/logo.svg"})
    Application.put_env(:amur, :providers, custom: Amur.PageTest.LogoProvider)

    assert logo_markup(render_page().resp_body) =~ ~s|src="/images/logo.svg"|
  end

  test "renders inline SVG markup that has no root svg element" do
    Application.put_env(:amur, :logo, {:svg, "<circle cx=\"12\" cy=\"12\" r=\"10\"/>"})
    Application.put_env(:amur, :providers, github: [])

    assert logo_markup(render_page().resp_body) =~ ~s|<circle cx="12" cy="12" r="10"/>|
  end

  test "strips the XML declaration and comments from a provider icon" do
    Application.put_env(:amur, :providers, custom: Amur.PageTest.InlineSvgProvider)

    body = render_page().resp_body

    # The page logo renders the provider's `logo/0` verbatim, so isolate the
    # button icon, which is the markup that goes through `inline_svg/1`.
    [icon] =
      Regex.run(~r|<span class="amur-provider-icon"[^>]*>(.*?)</span>|s, body,
        capture: :all_but_first
      )

    refute icon =~ "<?xml"
    refute icon =~ "<!--"
    refute icon =~ ~s|width="24"|
    refute icon =~ ~s|height="24"|
    assert icon =~ ~s|viewBox="0 0 24 24"|
  end

  test "returns nil for an asset with no filename" do
    conn = Plug.Test.conn(:get, "/auth/")

    assert Amur.Page.asset(conn, [""]) == nil
  end

  test "returns nil for a directory path" do
    conn = Plug.Test.conn(:get, "/auth/")

    assert Amur.Page.asset(conn, [".."]) == nil
  end

  test "serves an unknown asset type as a binary download" do
    path = Path.join([:code.priv_dir(:amur), "static", "amur.txt"])
    File.write!(path, "hello")
    on_exit(fn -> File.rm(path) end)

    conn = Plug.Test.conn(:get, "/auth/amur.txt")
    conn = Amur.Page.asset(conn, ["amur.txt"])

    assert conn.status == 200

    assert Plug.Conn.get_resp_header(conn, "content-type") == [
             "application/octet-stream; charset=utf-8"
           ]

    assert conn.resp_body == "hello"
  end

  test "falls back to the first provider with an icon when the first has none" do
    Application.delete_env(:amur, :logo)
    Application.put_env(:amur, :providers, custom: Amur.PageTest.CustomProvider, github: [])

    markup = logo_markup(render_page().resp_body)

    assert markup =~ "<svg"
    assert markup =~ ~s|fill="currentColor"|
  end

  test "renders an empty page logo when no provider has an icon" do
    Application.delete_env(:amur, :logo)
    Application.put_env(:amur, :providers, custom: Amur.PageTest.CustomProvider)

    assert logo_markup(render_page().resp_body) ==
             ~s|<span class="amur-logo" aria-hidden="true"></span>|
  end

  test "inlines a provider icon that has no root svg element" do
    Application.put_env(:amur, :providers, custom: Amur.PageTest.NoRootSvgProvider)

    body = render_page().resp_body

    assert body =~ ~s|<circle cx="12" cy="12" r="10"/>|
  end
end

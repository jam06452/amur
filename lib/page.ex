defmodule Amur.Page do
  @moduledoc """
  Renders the Amur sign-in page and serves its static assets.

  The page is a plain Plug, so it works the same in a Phoenix application and
  in a standalone `Plug.Router`. It lists every provider configured under
  `:amur, :providers` and links each one to `/auth/:provider`, which starts the
  OAuth flow handled by `Amur.Router`.

  `Amur.Router` serves the page automatically at the mount point (for example
  `GET /auth` when mounted with `forward "/auth", Amur.Router`). The page and
  its assets are read from Amur's own `priv/` directory, so no files need to be
  copied into the host application.

  The template is compiled into `render_page/3` when Amur is compiled, and the
  template file is registered as an external resource, so editing it rebuilds
  the page on the next compile. The provider list is resolved per request, so
  adding a provider to the application configuration is reflected immediately.
  """

  import Plug.Conn

  @templates_dir Path.join([:code.priv_dir(:amur), "templates"])
  @static_dir Path.join([:code.priv_dir(:amur), "static"])
  @template Path.join(@templates_dir, "sign_in.html.eex")

  @external_resource @template

  require EEx

  EEx.function_from_file(:defp, :render_page, @template, [
    :providers,
    :app_name,
    :logo,
    :base,
    :icon,
    :label
  ])

  # Display names for providers whose atom does not title-case cleanly, either
  # because it contains an underscore or because the brand uses specific
  # capitalisation. Providers not listed here fall back to title case.
  @provider_labels %{
    auth0: "Auth0",
    azure_ad: "Azure AD",
    basecamp: "Basecamp",
    bitbucket: "Bitbucket",
    digital_ocean: "DigitalOcean",
    discord: "Discord",
    facebook: "Facebook",
    github: "GitHub",
    gitlab: "GitLab",
    google: "Google",
    hackclub: "Hack Club",
    instagram: "Instagram",
    line: "LINE",
    linkedin: "LinkedIn",
    slack: "Slack",
    spotify: "Spotify",
    strava: "Strava",
    stripe: "Stripe",
    telegram: "Telegram",
    twitch: "Twitch",
    twitter: "Twitter (X)",
    vk: "VK",
    zitadel: "Zitadel"
  }

  @doc """
  Renders the sign-in page for the configured providers.

  Responds with `200` and an HTML body. When no provider is configured the
  response is a `404` explaining that Amur has no providers to sign in with,
  which is more useful than an empty page.

  Asset and provider links are built from the mount point recorded in
  `conn.script_name`, so the page works wherever `Amur.Router` is mounted
  rather than assuming `/auth`.
  """
  def render(conn) do
    case Amur.Config.configured_providers() do
      [] ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(404, "No Amur providers are configured.")

      providers ->
        base = base_path(conn)

        body =
          render_page(
            providers,
            app_name(),
            logo(providers),
            base,
            &provider_icon/1,
            &provider_label/1
          )

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, body)
    end
  end

  # Provider icons are inlined so their `currentColor` fills follow the page's
  # text colour and stay visible in dark mode. A provider without a bundled icon
  # falls back to an empty string, leaving the button label on its own.
  defp provider_icon(provider) do
    case provider_logo(provider) do
      {:svg, markup} -> inline_svg(markup)
      {:path, path} -> ~s|<img src="#{path}" alt="" />|
      :error -> ""
    end
  end

  # Resolves the logo for a single provider.
  #
  # A custom provider module can supply its own logo through the `logo/0`
  # callback, in any of the forms accepted by the `:logo` configuration. When
  # the module returns `:error`, or the provider is a built-in, the bundled
  # `priv/static/<provider>.svg` asset is used instead.
  defp provider_logo(provider) do
    case custom_logo(provider) do
      :error -> bundled_logo(provider)
      resolved -> resolved
    end
  end

  defp custom_logo(provider) do
    with {:ok, {module, _config}} <- Amur.Config.resolve(provider),
         true <- function_exported?(module, :logo, 0) do
      resolve_logo(module.logo())
    else
      _ -> :error
    end
  end

  defp bundled_logo(provider) do
    case File.read(asset_file(provider)) do
      {:ok, markup} -> {:svg, markup}
      {:error, _reason} -> :error
    end
  end

  # Human-readable provider name for the button label.
  defp provider_label(provider) do
    Map.get_lazy(@provider_labels, provider, fn ->
      provider
      |> to_string()
      |> String.split("_")
      |> Enum.map_join(" ", &String.capitalize/1)
    end)
  end

  # Strips the XML declaration and comments so the markup is valid when inlined
  # into an HTML document, and drops the fixed width/height from the root `<svg>`
  # so CSS controls the size. Only the opening tag is touched: child elements
  # such as `<rect>` carry their own width/height, which must be preserved.
  defp inline_svg(markup) do
    markup
    |> String.replace(~r/^\s*<\?xml[^>]*\?>/m, "")
    |> String.replace(~r/<!--.*?-->/s, "")
    |> strip_root_dimensions()
    |> String.trim()
  end

  defp strip_root_dimensions(markup) do
    case Regex.run(~r/<svg\b[^>]*>/s, markup) do
      [tag] ->
        cleaned = String.replace(tag, ~r/\s(?:width|height)="[^"]*"/, "")
        String.replace(markup, tag, cleaned, global: false)

      nil ->
        markup
    end
  end

  # The mount point of `Amur.Router`, without a trailing slash. Plug records the
  # prefix consumed by `forward` in `script_name`, so a router mounted at
  # `/auth` yields `/auth` and one mounted at the root yields `""`.
  defp base_path(conn) do
    case conn.script_name do
      [] -> ""
      segments -> "/" <> Enum.join(segments, "/")
    end
  end

  @doc """
  Serves a static asset bundled with Amur.

  Only files that exist in Amur's `priv/static` directory are served, so a
  request cannot escape the directory. Returns `nil` when the asset is not
  found, letting the caller fall through to its own routing.
  """
  def asset(conn, path) do
    with {:ok, file} <- safe_asset_path(path),
         {:ok, contents} <- File.read(file) do
      conn
      |> put_resp_content_type(content_type(file))
      |> send_resp(200, contents)
    else
      _ -> nil
    end
  end

  # Resolves a request path to a file inside `priv/static`, rejecting any path
  # that would traverse outside it.
  defp safe_asset_path(path) do
    relative = path |> Enum.join("/") |> Path.basename()

    if relative == "" do
      :error
    else
      file = Path.join(@static_dir, relative)

      if File.regular?(file), do: {:ok, file}, else: :error
    end
  end

  defp content_type(file) do
    case Path.extname(file) do
      ".css" -> "text/css"
      ".svg" -> "image/svg+xml"
      _ -> "application/octet-stream"
    end
  end

  # Uses the configured application name when present, otherwise a neutral
  # fallback, so the heading reads naturally in both cases.
  defp app_name do
    case Application.get_env(:amur, :app_name) do
      nil -> "your account"
      name -> to_string(name)
    end
  end

  # Resolves the logo shown above the heading.
  #
  # The application can supply its own logo through the `:amur, :logo`
  # configuration, in any of these forms:
  #
  #   * `{:svg, markup}` - inline SVG markup, rendered as-is
  #   * `{:file, path}` - a local SVG file, read and inlined
  #   * `{:path, url}` - a URL served by the host application
  #   * a bare string - a local file when one exists at that path, otherwise a URL
  #
  # When nothing is configured the page falls back to the first provider that
  # has an icon, so it still shows something.
  defp logo(providers) do
    case resolve_logo(Application.get_env(:amur, :logo)) do
      :error -> {:svg, provider_icon(fallback_logo(providers))}
      resolved -> resolved
    end
  end

  # Normalizes a logo value into `{:svg, markup}` or `{:path, url}`, or `:error`
  # when it is missing or unusable. Shared by the page-level `:logo`
  # configuration and the per-provider `logo/0` callback.
  defp resolve_logo({:svg, markup}) when is_binary(markup), do: {:svg, markup}
  defp resolve_logo({:file, path}) when is_binary(path), do: read_logo_file(path)
  defp resolve_logo({:path, path}) when is_binary(path), do: {:path, path}

  defp resolve_logo(path) when is_binary(path) do
    if File.regular?(path), do: read_logo_file(path), else: {:path, path}
  end

  defp resolve_logo(_other), do: :error

  # Inlines a local SVG file so the page needs no extra request. A missing or
  # unreadable file falls back to the provider icon rather than failing the
  # whole page, since a logo is decoration.
  defp read_logo_file(path) do
    case File.read(path) do
      {:ok, markup} -> {:svg, markup}
      {:error, _reason} -> :error
    end
  end

  # Prefers a provider-specific logo, falling back to the first provider that
  # has one so the page always shows an icon when any asset is available.
  defp fallback_logo(providers) do
    Enum.find(providers, hd(providers), &(provider_logo(&1) != :error))
  end

  defp asset_file(provider), do: Path.join(@static_dir, "#{provider}.svg")
end

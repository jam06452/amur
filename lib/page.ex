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
  EEx.function_from_file(:defp, :render_page, @template, [:providers, :app_name, :logo, :base])

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
        body = render_page(providers, app_name(), logo(providers, base), base)

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, body)
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
  # has a bundled icon, so it still shows something.
  defp logo(providers, base) do
    case resolve_logo() do
      :error -> {:path, "#{base}/#{fallback_logo(providers)}.svg"}
      resolved -> resolved
    end
  end

  defp resolve_logo do
    case Application.get_env(:amur, :logo) do
      {:svg, markup} when is_binary(markup) ->
        {:svg, markup}

      {:file, path} when is_binary(path) ->
        read_logo_file(path)

      {:path, path} when is_binary(path) ->
        {:path, path}

      path when is_binary(path) ->
        if File.regular?(path), do: read_logo_file(path), else: {:path, path}

      _ ->
        :error
    end
  end

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
    Enum.find(providers, hd(providers), &File.regular?(asset_file(&1)))
  end

  defp asset_file(provider), do: Path.join(@static_dir, "#{provider}.svg")
end

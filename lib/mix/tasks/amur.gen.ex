defmodule Mix.Tasks.Amur.Gen do
  @shortdoc "Generates Amur auth boilerplate (router mount, AuthController, config)"

  @moduledoc """
  Generates the boilerplate needed to start using Amur in your application.

  `mix amur.gen` inspects your project's `mix.exs` to detect the OTP app,
  derives the web module (`AppWeb` when a Phoenix-style `lib/<app>_web` layout
  is present, otherwise `App`), and writes:

    * an `AuthController` module with `on_success/2` and `on_failure/2`
    * a `forward "/auth", Amur.Router` mount in your router
    * a `config :amur` block in `config/runtime.exs` wired to the generated
      controller, defaulting to the `github` provider

  No user input is required. Run it from your project root:

      mix amur.gen

  ## Options

    * `--provider` - provider atom used in the generated config (default: `github`)
    * `--all` - generate config for every built-in provider
      (cannot be combined with `--provider`)
    * `--app` - override the detected OTP app (rarely needed)
    * `--no-config`, `--no-router`, `--no-controller` - skip individual pieces

  ## Examples

      mix amur.gen
      mix amur.gen --provider google
      mix amur.gen --all
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [
          provider: :string,
          app: :string,
          all: :boolean,
          no_config: :boolean,
          no_router: :boolean,
          no_controller: :boolean
        ]
      )

    if opts[:all] && opts[:provider] do
      Mix.raise(
        "--provider and --all cannot be combined. " <>
          "Use --all to configure every built-in provider, " <>
          "or --provider <name> for a single one."
      )
    end

    app = detect_app(opts)
    app_mod = app |> Atom.to_string() |> Macro.camelize()

    providers =
      if opts[:all] do
        Amur.Config.built_in_providers()
      else
        [(opts[:provider] || "github") |> String.to_atom()]
      end

    phoenix? = phoenix?(app)
    web_mod = if phoenix?, do: "#{app_mod}Web", else: app_mod

    Mix.shell().info("Detected OTP app: #{inspect(app)} (module #{app_mod})")
    Mix.shell().info("Web module: #{web_mod} (#{if phoenix?, do: "Phoenix", else: "Plug"})")

    if opts[:all] do
      Mix.shell().info("Providers: all #{length(providers)} built-in providers")
    else
      Mix.shell().info("Default provider: #{hd(providers)}")
    end

    unless opts[:no_controller], do: gen_controller(web_mod, app, phoenix?)
    unless opts[:no_router], do: gen_router(app, phoenix?)
    unless opts[:no_config], do: gen_config(web_mod, providers)

    next_steps(web_mod, providers)
    :ok
  end

  defp detect_app(opts) do
    case opts[:app] do
      nil ->
        case Mix.Project.config()[:app] do
          nil ->
            Mix.raise("Could not detect OTP app. Run inside a Mix project or pass --app MyApp.")

          app ->
            app
        end

      app when is_binary(app) ->
        String.to_atom(app)
    end
  end

  defp phoenix?(app) do
    web_dir = "lib/#{app}_web"
    File.dir?(web_dir) or File.exists?("#{web_dir}.ex")
  end

  # auth controller

  defp gen_controller(web_mod, app, phoenix?) do
    path = controller_path(app, phoenix?)
    File.mkdir_p!(Path.dirname(path))

    if File.exists?(path) do
      Mix.shell().info("[skip] #{path} already exists")
    else
      File.write!(path, controller_contents(web_mod, phoenix?))
      Mix.shell().info("[gen] #{path}")
    end
  end

  defp controller_path(app, true), do: "lib/#{app}_web/controllers/auth_controller.ex"
  defp controller_path(app, false), do: "lib/#{app}/controllers/auth_controller.ex"

  defp controller_contents(web_mod, true) do
    """
    defmodule #{web_mod}.AuthController do
      use #{web_mod}, :controller

      def on_success(conn, %{user: user}) do
        conn
        |> put_flash(:info, "Logged in as \#{user[:email]}")
        |> redirect(to: "/")
        |> halt()
      end

      def on_failure(conn, _reason) do
        conn
        |> put_flash(:error, "Authentication failed")
        |> redirect(to: "/")
        |> halt()
      end
    end
    """
  end

  defp controller_contents(web_mod, false) do
    """
    defmodule #{web_mod}.AuthController do
      import Plug.Conn

      def on_success(conn, %{user: _user}) do
        redirect(conn, "/")
      end

      def on_failure(conn, _reason) do
        redirect(conn, "/")
      end

      defp redirect(conn, to) do
        conn
        |> put_resp_header("location", to)
        |> send_resp(302, "")
        |> halt()
      end
    end
    """
  end

  # router

  defp gen_router(app, phoenix?) do
    case find_router(app, phoenix?) do
      nil ->
        Mix.shell().info("[skip] could not find a router to patch (no action taken)")

      path ->
        patch_router(path, phoenix?)
    end
  end

  defp find_router(app, true) do
    path = "lib/#{app}_web/router.ex"
    if File.exists?(path), do: path, else: nil
  end

  defp find_router(_app, false) do
    Path.wildcard("lib/**/*.ex")
    |> Enum.find(fn p ->
      case File.read(p) do
        {:ok, contents} -> String.contains?(contents, "use Plug.Router")
        _ -> false
      end
    end)
  end

  defp patch_router(path, true) do
    contents = File.read!(path)

    if String.contains?(contents, "Amur.Router") do
      Mix.shell().info("[skip] #{path} already mounts Amur.Router")
    else
      has_browser? = String.contains?(contents, "pipeline :browser")
      new_contents = insert_before_final_end(contents, phoenix_router_block(has_browser?))
      File.write!(path, new_contents)
      Mix.shell().info("[gen] mounted Amur.Router in #{path}")
    end
  end

  defp patch_router(path, false) do
    contents = File.read!(path)

    if String.contains?(contents, "Amur.Router") do
      Mix.shell().info("[skip] #{path} already mounts Amur.Router")
    else
      block = "\n  forward(\"/auth\", to: Amur.Router)"

      new_contents =
        case Enum.find(["plug(:dispatch)", "plug :dispatch"], &String.contains?(contents, &1)) do
          nil ->
            insert_before_final_end(contents, block)

          anchor ->
            String.replace(contents, anchor, anchor <> block, global: false)
        end

      File.write!(path, new_contents)
      Mix.shell().info("[gen] mounted Amur.Router in #{path}")
    end
  end

  defp phoenix_router_block(true) do
    "\n  scope \"/auth\", alias: false do\n    pipe_through :browser\n    forward \"/\", Amur.Router\n  end"
  end

  defp phoenix_router_block(false) do
    "\n  forward \"/auth\", Amur.Router"
  end

  defp insert_before_final_end(contents, block) do
    lines = String.split(contents, "\n")

    case find_last_end_line(lines) do
      nil ->
        contents <> block <> "\n"

      idx ->
        {before, [last | rest]} = Enum.split(lines, idx)
        Enum.join(before ++ [block, last | rest], "\n")
    end
  end

  defp find_last_end_line(lines) do
    lines
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find_value(fn {line, idx} ->
      if String.trim(line) == "end", do: idx
    end)
  end

  # runtime config

  defp gen_config(web_mod, providers) do
    path = "config/runtime.exs"
    File.mkdir_p!("config")
    contents = if File.exists?(path), do: File.read!(path), else: ""

    if String.contains?(contents, "config :amur,") do
      Mix.shell().info("[skip] #{path} already has a config :amur block")
    else
      block = config_block(web_mod, providers)

      new_contents =
        if String.trim(contents) == "" do
          "import Config\n\n" <> block
        else
          String.trim_trailing(contents) <> "\n\n" <> block
        end

      File.write!(path, new_contents)
      Mix.shell().info("[gen] added config :amur to #{path}")
    end
  end

  defp config_block(web_mod, providers) do
    providers_block =
      providers
      |> Enum.map_join(",\n", fn provider ->
        env_prefix = provider |> Atom.to_string() |> String.upcase()

        "    #{provider}: [\n" <>
          "      client_id: System.fetch_env!(\"#{env_prefix}_CLIENT_ID\"),\n" <>
          "      client_secret: System.fetch_env!(\"#{env_prefix}_CLIENT_SECRET\")\n" <>
          "    ]"
      end)

    """
    config :amur,
      base_url: "http://localhost:4000",
      providers: [
    #{providers_block}
      ],
      on_success: &#{web_mod}.AuthController.on_success/2,
      on_failure: &#{web_mod}.AuthController.on_failure/2
    """
  end

  # next steps

  defp next_steps(web_mod, [provider]) do
    env_prefix = provider |> Atom.to_string() |> String.upcase()

    Mix.shell().info("")
    Mix.shell().info("Amur boilerplate generated. Next steps:")
    Mix.shell().info("  1. Set #{env_prefix}_CLIENT_ID and #{env_prefix}_CLIENT_SECRET env vars.")
    Mix.shell().info("  2. Add your callback logic to #{web_mod}.AuthController.on_success/2.")
    Mix.shell().info("  3. Run your app and visit /auth/#{provider}.")
  end

  defp next_steps(web_mod, providers) do
    env_prefixes =
      providers
      |> Enum.map_join(", ", fn provider -> provider |> Atom.to_string() |> String.upcase() end)

    Mix.shell().info("")
    Mix.shell().info("Amur boilerplate generated. Next steps:")

    Mix.shell().info(
      "  1. Set the #{env_prefixes}_CLIENT_ID and _CLIENT_SECRET env vars for each provider you plan to use."
    )

    Mix.shell().info("  2. Add your callback logic to #{web_mod}.AuthController.on_success/2.")

    Mix.shell().info(
      "  3. Run your app and visit /auth/<provider> (e.g. /auth/#{hd(providers)})."
    )
  end
end

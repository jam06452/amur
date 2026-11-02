defmodule Mix.Tasks.Amur.InstallTest do
  use ExUnit.Case, async: true

  defp apply_install(args, files \\ %{}) do
    {:ok, igniter, _messages} = apply_install_with_messages(args, files)
    igniter
  end

  defp apply_install_with_messages(args, files) do
    default_files = %{
      "lib/sample_web.ex" => """
      defmodule SampleWeb do
        def controller do
          quote do
            use Phoenix.Controller, namespace: SampleWeb
          end
        end
      end
      """,
      "lib/sample_web/router.ex" => """
      defmodule SampleWeb.Router do
        use Phoenix.Router

        pipeline :browser do
          plug :accepts, ["html"]
        end

        scope "/", SampleWeb do
          pipe_through :browser
        end
      end
      """
    }

    Igniter.Test.test_project(files: Map.merge(default_files, files))
    |> Igniter.compose_task("amur.install", args)
    |> Igniter.Test.apply_igniter()
  end

  test "generates Phoenix boilerplate with the default GitHub provider" do
    igniter = apply_install(["--app", "sample", "--yes"])

    auth_controller_path =
      igniter.assigns[:test_files]
      |> Map.keys()
      |> Enum.find(&String.ends_with?(&1, "auth_controller.ex"))

    assert auth_controller_path == "lib/sample_web/controllers/auth_controller.ex"
    auth_controller = igniter.assigns[:test_files][auth_controller_path]
    assert auth_controller =~ "defmodule SampleWeb.AuthController do"
    assert auth_controller =~ "@behaviour Amur.Callback"
    assert auth_controller =~ "on_success(conn, %{user: user})"
    assert auth_controller =~ "@impl true"
    assert auth_controller =~ "user[:email]"

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert router =~ "scope \"/auth\", alias: false do"
    assert router =~ "forward(\"/\", Amur.Router)"

    runtime = igniter.assigns[:test_files]["config/runtime.exs"]
    assert runtime =~ "config :amur,"
    assert runtime =~ "github: ["
    assert runtime =~ "System.fetch_env!(\"GITHUB_CLIENT_ID\")"
    assert runtime =~ "SampleWeb.AuthController.on_success/2"
    assert runtime =~ "System.get_env(\"BASE_URL\") || \"http://localhost:4000\""
    refute runtime =~ "Endpoint.url()"
    refute runtime =~ "AMUR_DOTENV_LOADER"
    assert runtime =~ "config_env() != :test"
    assert runtime =~ "System.put_env(key, val)"
    assert runtime =~ ~r/import Config\n\nif config_env\(\) != :test/
    assert {:ok, _} = Code.string_to_quoted(runtime)
  end

  test "infers the Phoenix web module when app is omitted" do
    igniter = apply_install(["--yes"])

    auth_controller_path =
      igniter.assigns[:test_files]
      |> Map.keys()
      |> Enum.find(&String.ends_with?(&1, "auth_controller.ex"))

    assert auth_controller_path == "lib/test_web/controllers/auth_controller.ex"
    auth_controller = igniter.assigns[:test_files][auth_controller_path]
    assert auth_controller =~ "defmodule TestWeb.AuthController do"
  end

  test "generates config for every built-in provider with --all" do
    igniter = apply_install(["--all", "--app", "sample", "--yes"])

    runtime = igniter.assigns[:test_files]["config/runtime.exs"]

    for provider <- Amur.Config.built_in_providers() do
      assert runtime =~ "#{provider}: ["

      unless provider in [:apple, :telegram, :zitadel] do
        env_prefix = provider |> Atom.to_string() |> String.upcase()
        assert runtime =~ "System.fetch_env!(\"#{env_prefix}_CLIENT_ID\")"
        assert runtime =~ "System.fetch_env!(\"#{env_prefix}_CLIENT_SECRET\")"
      end
    end
  end

  @tag :tmp_dir
  test "generated runtime config evaluates without Mix running", %{tmp_dir: tmp_dir} do
    igniter = apply_install(["--app", "sample", "--yes"])
    runtime_path = Path.join(tmp_dir, "runtime.exs")
    File.write!(runtime_path, igniter.assigns[:test_files]["config/runtime.exs"])

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["-e", "Config.Reader.read!(hd(System.argv()), env: :prod)", runtime_path],
        cd: tmp_dir,
        env: [{"GITHUB_CLIENT_ID", "client"}, {"GITHUB_CLIENT_SECRET", "secret"}],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  test "the installer compiles without its optional Igniter dependency" do
    source = Path.expand("../../../lib/mix/tasks/amur.install.ex", __DIR__)

    script = """
    false = Code.ensure_loaded?(Igniter)
    Code.compile_file(hd(System.argv()))
    try do
      Mix.Tasks.Amur.Install.run([])
    rescue
      e in Mix.Error -> IO.puts(Exception.message(e))
    end
    """

    {output, status} =
      System.cmd(System.find_executable("elixir"), ["-e", script, source], stderr_to_stdout: true)

    assert status == 0, output
    assert output =~ "requires Igniter"
  end

  @tag :tmp_dir
  test "generates the credentials required by nonstandard providers", %{tmp_dir: tmp_dir} do
    providers = "twitter,telegram,apple,auth0,zitadel"

    {:ok, igniter, %{notices: notices}} =
      apply_install_with_messages(["--app", "sample", "--provider", providers, "--yes"], %{})

    runtime_path = Path.join(tmp_dir, "runtime.exs")
    File.write!(runtime_path, igniter.assigns[:test_files]["config/runtime.exs"])

    # Evaluate the generated configuration so incorrect keyword keys, missing
    # environment variables, or invalid generated code fail together.
    env_keys =
      ~w(TWITTER_CLIENT_ID TWITTER_CLIENT_SECRET TELEGRAM_BOT_TOKEN TELEGRAM_ORIGIN
      TELEGRAM_RETURN_TO APPLE_CLIENT_ID APPLE_TEAM_ID APPLE_PRIVATE_KEY_ID APPLE_PRIVATE_KEY_PATH
      AUTH0_CLIENT_ID AUTH0_CLIENT_SECRET AUTH0_BASE_URL ZITADEL_CLIENT_ID ZITADEL_BASE_URL ZITADEL_RESOURCE_ID)

    script = """
    providers = Config.Reader.read!(hd(System.argv()), env: :test)[:amur][:providers]
    "TWITTER_CLIENT_ID" = providers[:twitter][:consumer_key]
    "TWITTER_CLIENT_SECRET" = providers[:twitter][:consumer_secret]
    "TELEGRAM_BOT_TOKEN" = providers[:telegram][:bot_token]
    "TELEGRAM_ORIGIN" = providers[:telegram][:origin]
    "TELEGRAM_RETURN_TO" = providers[:telegram][:return_to]
    "APPLE_TEAM_ID" = providers[:apple][:team_id]
    "APPLE_PRIVATE_KEY_ID" = providers[:apple][:private_key_id]
    "APPLE_PRIVATE_KEY_PATH" = providers[:apple][:private_key_path]
    "AUTH0_BASE_URL" = providers[:auth0][:base_url]
    "ZITADEL_BASE_URL" = providers[:zitadel][:base_url]
    "ZITADEL_RESOURCE_ID" = providers[:zitadel][:resource_id]
    nil = providers[:zitadel][:client_secret]
    """

    {output, status} =
      System.cmd(System.find_executable("elixir"), ["-e", script, runtime_path],
        env: Enum.map(env_keys, &{&1, &1}),
        stderr_to_stdout: true
      )

    assert status == 0, output
    for key <- env_keys, do: assert(Enum.any?(notices, &String.contains?(&1, key)))
    assert Enum.any?(notices, &String.contains?(&1, "preserving amur_state"))
  end

  test "--provider and --all are mutually exclusive" do
    assert_raise Mix.Error, fn ->
      apply_install(["--all", "--provider", "google", "--app", "sample"])
    end
  end

  test "generates config for a comma-separated provider list" do
    igniter = apply_install(["--app", "sample", "--provider", "github, google", "--yes"])
    runtime = igniter.assigns[:test_files]["config/runtime.exs"]

    assert runtime =~ "github: ["
    assert runtime =~ "google: ["
    assert runtime =~ "System.fetch_env!(\"GITHUB_CLIENT_ID\")"
    assert runtime =~ "System.fetch_env!(\"GOOGLE_CLIENT_ID\")"
  end

  test "adding a provider preserves existing credentials, base URL and callbacks" do
    igniter =
      apply_install(
        ["--app", "sample", "--provider", "github", "--yes"],
        %{
          "config/runtime.exs" => """
          import Config

          config :amur,
            base_url: "https://example.com",
            providers: [
              google: [client_id: "existing-google", client_secret: "existing-secret"],
              github: [client_id: "existing-github", client_secret: "existing-secret"]
            ],
            on_success: &Sample.handle_success/2,
            on_failure: &Sample.handle_failure/2
          """
        }
      )

    runtime = igniter.assigns[:test_files]["config/runtime.exs"]
    assert runtime =~ "existing-google"
    assert runtime =~ "existing-github"
    assert runtime =~ ~s|base_url: "https://example.com"|
    assert runtime =~ "Sample.handle_success/2"
    assert runtime =~ "Sample.handle_failure/2"
  end

  test "adds a provider without dropping providers omitted from the command" do
    igniter =
      apply_install(
        ["--app", "sample", "--provider", "github", "--yes"],
        %{
          "config/runtime.exs" => """
          import Config
          config :amur, providers: [google: [client_id: "existing", client_secret: "existing"]]
          """
        }
      )

    runtime = igniter.assigns[:test_files]["config/runtime.exs"]
    assert runtime =~ "google: ["
    assert runtime =~ "github: ["
    assert runtime =~ "System.fetch_env!(\"GITHUB_CLIENT_ID\")"
  end

  test "does not require a browser pipeline" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => """
          defmodule SampleWeb.Router do
            use Phoenix.Router
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    refute router =~ "pipe_through :browser"
    assert router =~ "forward(\"/\", Amur.Router)"
  end

  test "does not generate callback captures when the controller is skipped" do
    igniter = apply_install(["--app", "sample", "--no-controller", "--no-config", "--yes"])
    runtime = igniter.assigns[:test_files]["config/runtime.exs"] || ""

    refute runtime =~ "AuthController.on_success"
    refute runtime =~ "AuthController.on_failure"
  end

  test "rejects provider names that are not valid Elixir identifiers" do
    assert_raise Mix.Error, ~r/Invalid provider/, fn ->
      apply_install(["--app", "sample", "--provider", "foo-bar", "--yes"])
    end
  end

  test "rejects unknown built-in providers" do
    assert_raise Mix.Error, ~r/Unknown built-in provider/, fn ->
      apply_install(["--app", "sample", "--provider", "nope", "--yes"])
    end
  end

  test "can skip router generation" do
    igniter = apply_install(["--app", "sample", "--no-router", "--yes"])

    refute igniter.assigns[:test_files]["lib/sample_web/router.ex"] =~ "forward"
  end

  test "does not ask to remount an existing router when generation is skipped" do
    {:ok, _igniter, %{notices: notices}} =
      apply_install_with_messages(
        ["--app", "sample", "--page", "--no-router", "--yes"],
        %{
          "lib/sample_web/router.ex" => """
          defmodule SampleWeb.Router do
            use Phoenix.Router

            scope "/auth", alias: false do
              forward "/", Amur.Router
            end
          end
          """
        }
      )

    assert Enum.any?(notices, &String.contains?(&1, "Open the sign-in page at"))
    refute Enum.any?(notices, &String.contains?(&1, "Mount Amur.Router in your router"))
  end

  test "does not point at an unmounted route when --no-router is passed" do
    # `--no-router` means the user opted out of mounting, so the installer knows
    # Amur.Router is not mounted and must not point at `/auth` as if it were.
    # The step tells the user to mount it first, then gives the URL.
    {:ok, _igniter, %{notices: notices}} =
      apply_install_with_messages(["--app", "sample", "--no-router", "--yes"], %{})

    assert Enum.any?(notices, &String.contains?(&1, "Mount Amur.Router in your router"))
    refute Enum.any?(notices, &String.contains?(&1, "Initiate an OAuth flow at"))
    refute Enum.any?(notices, &String.contains?(&1, "Open the sign-in page at"))
  end

  test "leaves an existing auth controller unchanged" do
    existing = """
    defmodule SampleWeb.AuthController do
      def on_success(conn, _context), do: conn
      def on_failure(conn, _reason), do: conn
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{"lib/sample_web/controllers/auth_controller.ex" => existing}
      )

    assert igniter.assigns[:test_files]["lib/sample_web/controllers/auth_controller.ex"] ==
             existing
  end

  test "patches a standalone Plug router with an auth forward" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router
            plug :match
            plug :dispatch
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert router =~ ~s|forward("/auth", to: Amur.Router)|
  end

  test "does not duplicate an existing standalone auth forward" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router
            forward("/auth", to: Amur.Router)
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert length(Regex.scan(~r/forward\(\"\/auth\"[^\n]*Amur\.Router/, router)) == 1
  end

  test "warns when no standalone Plug router can be found" do
    {:ok, _igniter, %{warnings: warnings}} =
      apply_install_with_messages(
        ["--app", "sample", "--no-controller", "--no-config", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample.ex" => "defmodule Sample do\nend\n"
        }
      )

    assert Enum.any?(
             warnings,
             &String.contains?(&1, "Could not find a Plug.Router module to patch.")
           )
  end

  test "does not point at an unmounted route when no Plug router can be found" do
    # With config generation enabled the next steps reach the flow step. Since no
    # Plug.Router was patched, the user must be told to mount Amur.Router rather
    # than pointed at a route that was never mounted. The controller is supplied
    # so config generation is permitted without `--no-controller`.
    {:ok, _igniter, %{notices: notices}} =
      apply_install_with_messages(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample.ex" => "defmodule Sample do\nend\n",
          "lib/sample_web/controllers/auth_controller.ex" =>
            "defmodule SampleWeb.AuthController do\nend\n"
        }
      )

    assert Enum.any?(notices, &String.contains?(&1, "Mount Amur.Router in your router"))
    refute Enum.any?(notices, &String.contains?(&1, "Initiate an OAuth flow at"))
    refute Enum.any?(notices, &String.contains?(&1, "Open the sign-in page at"))
  end

  test "requires an existing controller when configuration is requested without generation" do
    assert_raise Mix.Error, ~r/--no-controller cannot be combined/, fn ->
      apply_install(["--app", "sample", "--no-controller", "--yes"])
    end
  end

  test "upgrades an existing dotenv guard without duplicating or replacing the loader" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "config/runtime.exs" => """
          import Config
          if Mix.env() != :test and File.exists?(".env") do
          ".env"
          |> File.read!()
          |> String.split("\n", trim: true)
          |> Enum.each(fn line ->
            case String.split(line, "=", parts: 2) do
              [key, val] -> System.put_env(key, val)
              _ -> :ok
            end
            end)
          end
          """
        }
      )

    runtime = igniter.assigns[:test_files]["config/runtime.exs"]
    assert length(Regex.scan(~r/File\.exists\?\("\.env"\)/, runtime)) == 1
    assert runtime =~ "config_env() != :test"
    refute runtime =~ "Mix.env()"
    refute runtime =~ "Enum.reject"
  end

  test "adds the dotenv loader before a runtime file without Config import" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "config/runtime.exs" => """
          System.put_env("EXISTING", "true")
          """
        }
      )

    runtime = igniter.assigns[:test_files]["config/runtime.exs"]
    assert runtime =~ "File.exists?(\".env\")"
    {loader_index, _} = :binary.match(runtime, "File.exists?(\".env\")")
    {existing_index, _} = :binary.match(runtime, "System.put_env(\"EXISTING\", \"true\")")
    assert loader_index < existing_index
  end

  test "reports generated boilerplate without runtime configuration" do
    igniter = apply_install(["--app", "sample", "--no-config", "--yes"])

    refute Map.has_key?(igniter.assigns[:test_files], "config/runtime.exs")
  end

  test "--page records the application name for the sign-in page" do
    igniter = apply_install(["--app", "sample", "--page", "--yes"])

    runtime = igniter.assigns[:test_files]["config/runtime.exs"]
    assert runtime =~ ~s|app_name: "sample"|
  end

  test "--page points the next steps at the sign-in page" do
    {:ok, _igniter, %{notices: notices}} =
      apply_install_with_messages(["--app", "sample", "--page", "--yes"], %{})

    assert Enum.any?(notices, &String.contains?(&1, "Open the sign-in page at"))
    assert Enum.any?(notices, &String.contains?(&1, "/auth"))
  end

  test "omits the app name when --page is not passed" do
    igniter = apply_install(["--app", "sample", "--yes"])

    runtime = igniter.assigns[:test_files]["config/runtime.exs"]
    refute runtime =~ "app_name:"
  end

  test "--page does not write config when --no-config is set" do
    igniter = apply_install(["--app", "sample", "--page", "--no-config", "--yes"])

    refute Map.has_key?(igniter.assigns[:test_files], "config/runtime.exs")
  end

  test "does not add a second forward when the router already mounts Amur" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", Amur.Router
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",\s*Amur\.Router/, router)) == 1
  end

  test "does not mistake a quoted mount in another module for the selected router" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => """
          defmodule SampleWeb.Router do
            use Phoenix.Router
          end

          defmodule SampleWeb.RouterHelpers do
            defmacro auth_routes do
              quote do
                scope "/auth", alias: false do
                  forward "/", Amur.Router
                end
              end
            end
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",\s*Amur\.Router/, router)) == 2
  end

  test "does not mistake a prefixed auth scope for the root mount" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => """
          defmodule SampleWeb.Router do
            use Phoenix.Router

            scope "/admin", alias: false do
              scope "/auth", alias: false do
                forward "/", Amur.Router
              end
            end
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",\s*Amur\.Router/, router)) == 2
  end

  test "resolves aliases at the forward instead of declarations later in the module" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => """
          defmodule SampleWeb.Router do
            use Phoenix.Router
            alias Amur.Router, as: AuthRouter

            scope "/auth", alias: false do
              forward "/", AuthRouter
            end

            alias Other.Router, as: AuthRouter
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",/, router)) == 1
  end

  test "does not mistake Phoenix controller aliasing for an Amur mount" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => """
          defmodule SampleWeb.Router do
            use Phoenix.Router

            scope "/auth", SampleWeb do
              forward "/", Amur.Router
            end
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",\s*Amur\.Router/, router)) == 2
    assert router =~ ~s|scope "/auth", alias: false do|
  end

  test "recognizes a forward that disables Phoenix aliasing on the route itself" do
    igniter =
      apply_install(["--app", "sample", "--yes"], %{
        "lib/sample_web/router.ex" => """
        defmodule SampleWeb.Router do
          use Phoenix.Router

          scope "/auth", SampleWeb do
            forward "/", Amur.Router, [], alias: false
          end
        end
        """
      })

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",\s*Amur\.Router/, router)) == 1
  end

  @tag :tmp_dir
  test "an existing dotenv loader runs before newly generated credentials", %{tmp_dir: tmp_dir} do
    igniter =
      apply_install(["--app", "sample", "--yes"], %{
        "config/runtime.exs" => """
        import Config

        if Mix.env() != :test and File.exists?(".env") do
          ".env"
          |> File.read!()
          |> String.split("\\n", trim: true)
          |> Enum.each(fn line ->
            [key, val] = String.split(line, "=", parts: 2)
            System.put_env(key, val)
          end)
        end
        """
      })

    runtime_path = Path.join(tmp_dir, "runtime.exs")
    File.write!(runtime_path, igniter.assigns[:test_files]["config/runtime.exs"])
    File.write!(Path.join(tmp_dir, ".env"), "GITHUB_CLIENT_ID=id\nGITHUB_CLIENT_SECRET=secret\n")

    script = """
    providers = Config.Reader.read!(hd(System.argv()), env: :prod)[:amur][:providers]
    "id" = providers[:github][:client_id]
    "secret" = providers[:github][:client_secret]
    """

    {output, status} =
      System.cmd(System.find_executable("elixir"), ["-e", script, runtime_path],
        cd: tmp_dir,
        env: [{"GITHUB_CLIENT_ID", nil}, {"GITHUB_CLIENT_SECRET", nil}],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  @tag :tmp_dir
  test "a nested dotenv loader does not scope generated defaults to its environment", %{
    tmp_dir: tmp_dir
  } do
    igniter =
      apply_install(["--app", "sample", "--yes"], %{
        "config/runtime.exs" => """
        import Config

        if config_env() == :prod do
          if File.exists?(".env") do
            Enum.each([], fn {key, val} -> System.put_env(key, val) end)
          end
        end

        config :amur, providers: [github: [client_id: "existing", client_secret: "existing"]]
        """
      })

    runtime_path = Path.join(tmp_dir, "runtime.exs")
    File.write!(runtime_path, igniter.assigns[:test_files]["config/runtime.exs"])
    config = Config.Reader.read!(runtime_path, env: :test)[:amur]

    assert is_binary(config[:base_url])
    assert is_function(config[:on_success], 2)
    assert config[:providers][:github][:client_id] == "existing"
  end

  test "does not treat a dynamic scope path or alias as a root Amur mount" do
    for scope <- ["path: @prefix, alias: false", "path: \"/\", alias: @web_module"] do
      igniter =
        apply_install(["--app", "sample", "--yes"], %{
          "lib/sample_web/router.ex" => """
          defmodule SampleWeb.Router do
            use Phoenix.Router
            @prefix "/admin"
            @web_module SampleWeb
            scope #{scope} do
              forward "/auth", Amur.Router
            end
          end
          """
        })

      router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
      assert router =~ "scope \"/auth\", alias: false"
      assert router =~ "forward(\"/\", Amur.Router)"
    end
  end

  test "warns when an aliased standalone Plug router cannot be located" do
    {:ok, _igniter, %{warnings: warnings, notices: notices}} =
      apply_install_with_messages(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/weird/thing.ex" => """
          alias Sample.Router

          defmodule Router do
            use Plug.Router
            plug :match
            plug :dispatch
          end
          """
        }
      )

    assert Enum.any?(
             warnings,
             &String.contains?(&1, "Could not find the Plug router Sample.Router")
           )

    assert Enum.any?(notices, &String.contains?(&1, "Mount Amur.Router in your router"))
    refute Enum.any?(notices, &String.contains?(&1, "Initiate an OAuth flow at"))
  end

  test "adds the /auth mount when Amur is forwarded at a different path" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/oauth", alias: false do
        pipe_through :browser
        forward "/", Amur.Router
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert router =~ ~s|scope "/auth", alias: false do|
    assert length(Regex.scan(~r/forward\(?\s*"\/"\s*,\s*Amur\.Router/, router)) == 2
  end

  test "adds the /auth mount when Amur is only forwarded in a nested scope" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser

        scope "/nested", alias: false do
          forward "/", Amur.Router
        end
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/"\s*,\s*Amur\.Router/, router)) == 2
  end

  test "page-only mode leaves general configuration untouched" do
    existing = %{
      "config/runtime.exs" => """
      import Config

      config :amur,
        base_url: "https://example.com",
        providers: [github: [client_id: "x", client_secret: "y"]]
      """
    }

    igniter =
      apply_install(
        ["--page", "--no-router", "--no-controller", "--app", "sample", "--yes"],
        existing
      )

    runtime = igniter.assigns[:test_files]["config/runtime.exs"]
    assert runtime =~ ~s|app_name: "sample"|
    assert runtime =~ ~s|base_url: "https://example.com"|
    refute runtime =~ "System.get_env(\"BASE_URL\")"
    refute runtime =~ "File.exists?(\".env\")"
    refute runtime =~ "google: ["
  end

  test "page-only next steps preserve the project's provider and callback choices" do
    {:ok, _igniter, %{notices: notices}} =
      apply_install_with_messages(
        ["--page", "--no-router", "--no-controller", "--app", "sample", "--yes"],
        %{
          "config/runtime.exs" => """
          import Config

          config :amur,
            providers: [google: [client_id: "existing", client_secret: "existing"]],
            on_success: &Sample.handle_success/2,
            on_failure: &Sample.handle_failure/2
          """
        }
      )

    refute Enum.any?(notices, &String.contains?(&1, "GITHUB_CLIENT"))
    refute Enum.any?(notices, &String.contains?(&1, "AuthController"))
    refute Enum.any?(notices, &String.contains?(&1, "/auth/github"))
    assert Enum.any?(notices, &String.contains?(&1, "sign-in page"))
  end

  test "adds the page config to a project that already has Amur installed" do
    existing = %{
      "lib/sample_web/router.ex" => """
      defmodule SampleWeb.Router do
        use Phoenix.Router

        pipeline :browser do
          plug :accepts, ["html"]
        end

        scope "/auth", alias: false do
          pipe_through :browser
          forward "/", Amur.Router
        end
      end
      """,
      "lib/sample_web/controllers/auth_controller.ex" => """
      defmodule SampleWeb.AuthController do
        @behaviour Amur.Callback
        def on_success(conn, _), do: conn
        def on_failure(conn, _), do: conn
      end
      """,
      "config/runtime.exs" => """
      import Config

      config :amur,
        providers: [
          github: [
            client_id: System.fetch_env!("GITHUB_CLIENT_ID"),
            client_secret: System.fetch_env!("GITHUB_CLIENT_SECRET")
          ]
        ]
      """
    }

    {:ok, igniter, %{warnings: warnings, notices: notices}} =
      apply_install_with_messages(
        ["--provider", "github,google", "--page", "--app", "sample", "--yes"],
        existing
      )

    assert warnings == []
    assert Enum.any?(notices, &String.contains?(&1, "already forwards to Amur.Router"))

    runtime = igniter.assigns[:test_files]["config/runtime.exs"]
    assert runtime =~ "github: ["
    assert runtime =~ "google: ["
    assert runtime =~ ~s|app_name: "sample"|

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",\s*Amur\.Router/, router)) == 1

    controller = igniter.assigns[:test_files]["lib/sample_web/controllers/auth_controller.ex"]
    assert controller =~ "def on_success(conn, _), do: conn"
  end

  test "adds only the page config with --page --no-router --no-controller" do
    existing = %{
      "lib/sample_web/router.ex" => """
      defmodule SampleWeb.Router do
        use Phoenix.Router

        pipeline :browser do
          plug :accepts, ["html"]
        end

        scope "/auth", alias: false do
          pipe_through :browser
          forward "/", Amur.Router
        end
      end
      """,
      "lib/sample_web/controllers/auth_controller.ex" => """
      defmodule SampleWeb.AuthController do
        @behaviour Amur.Callback
        def on_success(conn, _), do: conn
        def on_failure(conn, _), do: conn
      end
      """,
      "config/runtime.exs" => """
      import Config

      config :amur, providers: [github: []]
      """
    }

    {:ok, igniter, %{warnings: warnings}} =
      apply_install_with_messages(
        ["--page", "--no-router", "--no-controller", "--app", "sample", "--yes"],
        existing
      )

    assert warnings == []

    runtime = igniter.assigns[:test_files]["config/runtime.exs"]
    assert runtime =~ ~s|app_name: "sample"|

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",\s*Amur\.Router/, router)) == 1
  end

  test "recognizes an existing mount written through an alias" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router
      alias Amur.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", Router
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",\s*Router/, router)) == 1
    refute router =~ ~s|forward("/", Amur.Router)|
  end

  test "recognizes an existing mount written through an `as:` alias" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router
      alias Amur.Router, as: AmurAuth

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", AmurAuth
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",\s*AmurAuth/, router)) == 1
  end

  test "recognizes an existing mount written as a fully qualified Elixir alias" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", Elixir.Amur.Router
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",\s*Elixir\.Amur\.Router/, router)) == 1
  end

  test "adds the mount when the alias points at a different module" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router
      alias Other.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", Router
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert router =~ ~s|forward("/", Amur.Router)|
  end

  test "adds the mount when the auth scope forwards a non-Amur router" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", Other.Router
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert router =~ ~s|forward("/", Amur.Router)|
  end

  test "adds the mount when the auth scope forwards a different path" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/nested", Amur.Router
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert router =~ ~s|forward("/", Amur.Router)|
  end

  test "patches a Plug router that has no dispatch plug" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router
            plug :match
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert router =~ ~s|forward("/auth", to: Amur.Router)|
  end

  test "patches a Plug router that has no plug calls at all" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router

            def hello, do: :world
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert router =~ ~s|forward("/auth", to: Amur.Router)|
  end

  test "leaves a Plug router untouched when it has no use Plug.Router" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            plug :match
            plug :dispatch
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    refute router =~ "forward"
  end

  test "does not wire callbacks when the controller is skipped" do
    igniter =
      apply_install(
        ["--app", "sample", "--no-controller", "--no-config", "--yes"],
        %{}
      )

    runtime = igniter.assigns[:test_files]["config/runtime.exs"] || ""
    refute runtime =~ "on_success"
  end

  test "reports the existing controller in the next steps when skipped" do
    existing = %{
      "lib/sample_web/controllers/auth_controller.ex" => """
      defmodule SampleWeb.AuthController do
        @behaviour Amur.Callback
        def on_success(conn, _), do: conn
        def on_failure(conn, _), do: conn
      end
      """
    }

    {:ok, _igniter, %{notices: notices}} =
      apply_install_with_messages(
        ["--app", "sample", "--no-controller", "--yes"],
        existing
      )

    assert Enum.any?(notices, &String.contains?(&1, "Verify the existing"))
  end

  test "reports no runtime configuration in the next steps when config is skipped" do
    {:ok, _igniter, %{notices: notices}} =
      apply_install_with_messages(["--app", "sample", "--no-config", "--yes"], %{})

    assert Enum.any?(notices, &String.contains?(&1, "No runtime configuration was generated"))
  end

  test "reports the OAuth flow step when --page is not passed" do
    {:ok, _igniter, %{notices: notices}} =
      apply_install_with_messages(["--app", "sample", "--yes"], %{})

    assert Enum.any?(notices, &String.contains?(&1, "Initiate an OAuth flow at"))
  end

  test "falls back to the GitHub example when no provider is configured" do
    {:ok, _igniter, %{notices: notices}} =
      apply_install_with_messages(["--app", "sample", "--yes"], %{})

    assert Enum.any?(notices, &String.contains?(&1, "/auth/github"))
  end

  test "does not duplicate an existing Plug router forward written as an alias" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router
            alias Amur.Router
            plug :match
            plug :dispatch
            forward("/auth", to: Router)
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/auth"/, router)) == 1
  end

  test "does not duplicate an existing Plug router forward written as an alias list" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router
            plug :match
            plug :dispatch
            forward("/auth", to: Amur.Router)
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/auth"/, router)) == 1
  end

  test "adds a Plug router forward when the existing one points elsewhere" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router
            plug :match
            plug :dispatch
            forward("/other", to: Other.Router)
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert router =~ ~s|forward("/auth", to: Amur.Router)|
  end

  test "leaves a module without use Plug.Router untouched" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/not_a_router.ex" => """
          defmodule Sample.NotARouter do
            plug :match
            plug :dispatch
          end
          """
        }
      )

    source = igniter.assigns[:test_files]["lib/sample/not_a_router.ex"]
    refute source =~ "forward"
  end

  test "adds the mount when the router module cannot be found" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router
            plug :match
            plug :dispatch
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert router =~ ~s|forward("/auth", to: Amur.Router)|
  end

  test "warns when the detected Phoenix router cannot be located" do
    # `select_router/1` resolves the router through an alias, so it can name a
    # module that `find_module/2` cannot find. The installer must warn rather
    # than crash while trying to read the router's pipelines.
    {:ok, _igniter, %{warnings: warnings, notices: notices}} =
      apply_install_with_messages(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.NotARouter do\nend\n",
          "lib/weird/thing.ex" => """
          alias SampleWeb.Router

          defmodule Router do
            use Phoenix.Router

            pipeline :browser do
              plug :accepts, ["html"]
            end

            scope "/", SampleWeb do
              pipe_through :browser
            end
          end
          """
        }
      )

    assert Enum.any?(
             warnings,
             &String.contains?(
               &1,
               "Could not find the Phoenix router SampleWeb.Router to mount Amur.Router."
             )
           )

    # The next steps must not point the user at a route that was never mounted.
    assert Enum.any?(notices, &String.contains?(&1, "Mount Amur.Router in your router"))
    refute Enum.any?(notices, &String.contains?(&1, "Open the sign-in page at"))
    refute Enum.any?(notices, &String.contains?(&1, "Initiate an OAuth flow at"))
  end

  test "ignores an alias whose target is not a module alias" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router
      alias __MODULE__

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", Amur.Router
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",\s*Amur\.Router/, router)) == 1
  end

  test "recognizes a mount written as a bare module argument" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", Amur.Router
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",\s*Amur\.Router/, router)) == 1
  end

  test "recognizes a Plug router forward written as a bare module argument" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router
            plug :match
            plug :dispatch
            forward "/auth", Amur.Router
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/auth"/, router)) == 1
  end

  test "recognizes an alias declared with an atom `as:` name" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router
      alias Amur.Router, as: :AmurAuth

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", AmurAuth
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",\s*AmurAuth/, router)) == 1
  end

  test "recognizes a mount when another scope precedes the auth scope" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/", SampleWeb do
        pipe_through :browser
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", Amur.Router
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",\s*Amur\.Router/, router)) == 1
  end

  test "ignores a forward whose path is not a literal string" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward @path, Amur.Router
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert router =~ ~s|forward("/", Amur.Router)|
  end

  test "ignores a Plug router forward whose path is not a literal string" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router
            plug :match
            plug :dispatch
            forward @path, Amur.Router
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert router =~ ~s|forward("/auth", to: Amur.Router)|
  end

  test "ignores a Plug router forward with a non-module target" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router
            plug :match
            plug :dispatch
            forward "/auth", @router
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert router =~ ~s|forward("/auth", to: Amur.Router)|
  end

  test "ignores a Plug router forward with an unrelated arity" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router
            plug :match
            plug :dispatch
            forward "/auth"
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert router =~ ~s|forward("/auth", to: Amur.Router)|
  end

  test "ignores a Plug router forward with a non-keyword second argument" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router
            plug :match
            plug :dispatch
            forward "/auth", ["not", "a", "keyword"]
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert router =~ ~s|forward("/auth", to: Amur.Router)|
  end

  test "ignores a Plug router forward whose target is a variable" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router
            plug :match
            plug :dispatch
            forward "/auth", to: router
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert router =~ ~s|forward("/auth", to: Amur.Router)|
  end

  test "ignores a Phoenix forward whose target is a variable" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", router
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert router =~ ~s|forward("/", Amur.Router)|
  end

  test "ignores a Phoenix forward whose target is a non-module literal" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", "not a module"
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert router =~ ~s|forward("/", Amur.Router)|
  end

  test "ignores an alias whose target is a variable" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router
      alias unquote(Some.Module)

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", Amur.Router
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",\s*Amur\.Router/, router)) == 1
  end

  test "ignores an alias with an `as:` value that is not a name" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router
      alias Amur.Router, as: unquote(:AmurAuth)

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", Amur.Router
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",\s*Amur\.Router/, router)) == 1
  end

  test "ignores an alias option that is not `as:`" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router
      alias Amur.Router, warn: false

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", Amur.Router
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",\s*Amur\.Router/, router)) == 1
  end

  test "ignores a Plug router forward whose target is a bare atom" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router
            plug :match
            plug :dispatch
            forward "/auth", :not_a_module
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert router =~ ~s|forward("/auth", to: Amur.Router)|
  end

  test "ignores a Plug router forward with a `to:` list that has no `to:` key" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router
            plug :match
            plug :dispatch
            forward "/auth", to: Amur.Router, host: "example.com"
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/auth"/, router)) == 1
  end

  test "ignores a Plug router forward with a non-`to` option before `to:`" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router
            plug :match
            plug :dispatch
            forward "/auth", host: "example.com", to: Amur.Router
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/auth"/, router)) == 1
  end

  test "ignores a Plug router forward with a non-keyword list second argument" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router
            plug :match
            plug :dispatch
            forward "/auth", ["not", "keyword"]
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert router =~ ~s|forward("/auth", to: Amur.Router)|
  end

  test "recognizes a mount in a scope declared without options" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth" do
        pipe_through :browser
        forward "/", Amur.Router
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",\s*Amur\.Router/, router)) == 1
  end

  test "recognizes a mount in a scope whose body is a single statement" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        forward "/", Amur.Router
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",\s*Amur\.Router/, router)) == 1
  end

  test "ignores a scope whose body is not a do block" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false, do: :nothing
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert router =~ ~s|forward("/", Amur.Router)|
  end

  test "warns when the Phoenix router cannot be located" do
    # `list_routers/1` scans every Elixir source, but `find_module/2` skips
    # `_test.exs` files, so a router defined there is selected yet cannot be
    # patched. The installer must warn rather than crash in `has_pipeline/3`.
    router = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/", SampleWeb do
        pipe_through :browser
      end
    end
    """

    {:ok, igniter, %{warnings: warnings}} =
      apply_install_with_messages(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Placeholder do\nend\n",
          "lib/sample_web/router_test.exs" => router
        }
      )

    assert Enum.any?(
             warnings,
             &String.contains?(&1, "Could not find the Phoenix router SampleWeb.Router")
           )

    assert igniter.assigns[:test_files]["lib/sample_web/router_test.exs"] =~ "use Phoenix.Router"
  end

  test "--no-router reports whether a Plug router already mounts Amur" do
    for mounted? <- [true, false] do
      forward = if mounted?, do: ~s(forward "/auth", to: Amur.Router), else: ""

      source = """
      defmodule Sample.Router do
        use Plug.Router
        plug :match
        #{forward}
        plug :dispatch
      end
      """

      {:ok, igniter, %{notices: notices}} =
        apply_install_with_messages(["--app", "sample", "--no-router", "--yes"], %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Placeholder do
end",
          "lib/sample/router.ex" => source
        })

      result = igniter.assigns[:test_files]["lib/sample/router.ex"]
      assert result =~ "forward" == mounted?
      assert Enum.any?(notices, &String.contains?(&1, "Initiate an OAuth flow at")) == mounted?
      assert Enum.any?(notices, &String.contains?(&1, "Mount Amur.Router")) == not mounted?
    end
  end

  test "recognizes pathless scopes and explicitly nil scope aliases" do
    for scope <- ["alias: false", ~s("/auth", alias: nil)] do
      path = if scope == "alias: false", do: "/auth", else: "/"

      source = """
      defmodule SampleWeb.Router do
        use Phoenix.Router
        scope #{scope} do
          forward "#{path}", Amur.Router
        end
      end
      """

      igniter =
        apply_install(["--app", "sample", "--yes"], %{"lib/sample_web/router.ex" => source})

      result = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
      assert length(Regex.scan(~r/forward/, result)) == 1
    end
  end

  test "a scope without settings does not count as a known mount" do
    source = """
    defmodule SampleWeb.Router do
      use Phoenix.Router
      scope do
        forward "/auth", Amur.Router
      end
    end
    """

    igniter = apply_install(["--app", "sample", "--yes"], %{"lib/sample_web/router.ex" => source})
    result = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert result =~ ~s(scope "/auth", alias: false)
  end

  test "upgrading a dotenv guard preserves unrelated runtime conditions" do
    source = """
    import Config

    if Mix.env() != :test and File.exists?(".env") do
      Enum.each([], fn {key, val} -> System.put_env(key, val) end)
    end

    if config_env() == :prod do
      config :sample, :unrelated, true
    end
    """

    igniter = apply_install(["--app", "sample", "--yes"], %{"config/runtime.exs" => source})
    runtime = igniter.assigns[:test_files]["config/runtime.exs"]
    refute runtime =~ "Mix.env()"
    assert runtime =~ "if config_env() == :prod do"
    assert runtime =~ "config :sample, :unrelated, true"
  end

  test "--no-router tolerates a router placeholder without a do block" do
    source = """
    defmodule SampleWeb.Router, [use(Phoenix.Router)]
    """

    {:ok, igniter, %{notices: notices}} =
      apply_install_with_messages(["--app", "sample", "--no-router", "--yes"], %{
        "lib/sample_web/router.ex" => source,
        "test/router_test.exs" => """
        defmodule SampleWeb.Router do
          use Phoenix.Router
        end
        """
      })

    refute igniter.assigns[:test_files]["lib/sample_web/router.ex"] =~ "forward"
    assert Enum.any?(notices, &String.contains?(&1, "Mount Amur.Router"))
  end
end

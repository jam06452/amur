defmodule Mix.Tasks.Amur.InstallTest do
  use ExUnit.Case, async: false

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
    assert runtime =~ "System.fetch_env!(\"BASE_URL\") || \"http://localhost:4000\""
    refute runtime =~ "Endpoint.url()"
    refute runtime =~ "AMUR_DOTENV_LOADER"
    assert runtime =~ "Mix.env() != :test"
    assert runtime =~ "System.put_env(key, val)"
    assert runtime =~ ~r/import Config\n\nif Mix\.env\(\) != :test/
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
      env_prefix = provider |> Atom.to_string() |> String.upcase()
      assert runtime =~ "System.fetch_env!(\"#{env_prefix}_CLIENT_ID\")"
      assert runtime =~ "System.fetch_env!(\"#{env_prefix}_CLIENT_SECRET\")"
    end
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

  test "requires an existing controller when configuration is requested without generation" do
    assert_raise Mix.Error, ~r/--no-controller cannot be combined/, fn ->
      apply_install(["--app", "sample", "--no-controller", "--yes"])
    end
  end

  test "does not add a duplicate dotenv loader" do
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
    refute runtime =~ "System.fetch_env!(\"BASE_URL\")"
    refute runtime =~ "File.exists?(\".env\")"
    refute runtime =~ "google: ["
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
end

defmodule Mix.Tasks.Amur.InstallTest do
  use ExUnit.Case, async: false

  defp apply_install(args, files \\ %{}) do
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
    |> then(fn igniter ->
      notices = igniter.notices

      igniter
      |> Igniter.Test.apply_igniter!()
      |> Igniter.assign(:install_notices, notices)
    end)
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
    assert runtime =~ "System.get_env(\"BASE_URL\", \"http://localhost:4000\")"
    refute runtime =~ "GITHUB_BASE_URL"
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

      if provider in [:auth0, :authentik, :aws_cognito, :keycloak, :okta, :shopify, :zitadel] do
        assert runtime =~
                 ~r/#{provider}: \[\s+base_url: System.fetch_env!\("#{env_prefix}_BASE_URL"\)/

        assert Enum.any?(
                 igniter.assigns[:install_notices],
                 &String.contains?(&1, "#{env_prefix}_BASE_URL")
               )
      else
        refute runtime =~ "#{env_prefix}_BASE_URL"
      end
    end

    assert {:ok, _} = Code.string_to_quoted(runtime)
  end

  test "generates provider base URLs alongside credentials for selected custom hosts" do
    igniter =
      apply_install(["--app", "sample", "--provider", "aws_cognito,keycloak,okta", "--yes"])

    runtime = igniter.assigns[:test_files]["config/runtime.exs"]

    for {provider, prefix} <- [
          aws_cognito: "AWS_COGNITO",
          keycloak: "KEYCLOAK",
          okta: "OKTA"
        ] do
      assert runtime =~
               """
                   #{provider}: [
                     base_url: System.fetch_env!("#{prefix}_BASE_URL"),
                     client_id: System.fetch_env!("#{prefix}_CLIENT_ID"),
                     client_secret: System.fetch_env!("#{prefix}_CLIENT_SECRET")
                   ]
               """
               |> String.trim()
    end

    refute runtime =~ "GITHUB_CLIENT_ID"
    assert {:ok, _} = Code.string_to_quoted(runtime)
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
end

defmodule Mix.Tasks.Amur.InstallTest do
  use Amur.Test.InstallHelpers, async: true

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

  test "--provider and --all are mutually exclusive" do
    assert_raise Mix.Error, fn ->
      apply_install(["--all", "--provider", "google", "--app", "sample"])
    end
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

  test "requires an existing controller when configuration is requested without generation" do
    assert_raise Mix.Error, ~r/--no-controller cannot be combined/, fn ->
      apply_install(["--app", "sample", "--no-controller", "--yes"])
    end
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

  test "fixture overrides and generated config are isolated between installs" do
    first =
      apply_install(["--app", "sample", "--provider", "google", "--yes"], %{
        "config/runtime.exs" => """
        import Config
        config :amur, base_url: "https://first.example"
        """
      })

    second = apply_install(["--app", "sample", "--yes"])
    first_runtime = first.assigns.test_files["config/runtime.exs"]
    second_runtime = second.assigns.test_files["config/runtime.exs"]

    assert first_runtime =~ "https://first.example"
    assert first_runtime =~ "google:"
    assert second_runtime =~ "github:"
    refute second_runtime =~ "https://first.example"
    refute second_runtime =~ "google:"
  end
end

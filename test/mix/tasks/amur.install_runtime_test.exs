defmodule Mix.Tasks.Amur.InstallRuntimeTest do
  use Amur.Test.InstallHelpers, async: true

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
end

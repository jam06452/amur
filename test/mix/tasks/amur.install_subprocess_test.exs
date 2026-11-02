defmodule Mix.Tasks.Amur.InstallRuntimeWithoutMixTest do
  use Amur.Test.InstallHelpers, async: true

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
end

defmodule Mix.Tasks.Amur.InstallWithoutIgniterTest do
  use ExUnit.Case, async: true

  test "the installer compiles without its optional Igniter dependency" do
    source = Path.expand("../../../lib/mix/tasks/amur.install.ex", __DIR__)
    inspector = Path.expand("../../../lib/installer/router.ex", __DIR__)

    script = """
    false = Code.ensure_loaded?(Igniter)
    Code.compile_file(Enum.at(System.argv(), 1))
    false = Code.ensure_loaded?(Amur.Installer.Router)
    Code.compile_file(hd(System.argv()))
    try do
      Mix.Tasks.Amur.Install.run([])
    rescue
      e in Mix.Error -> IO.puts(Exception.message(e))
    end
    """

    {output, status} =
      System.cmd(System.find_executable("elixir"), ["-e", script, source, inspector],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "requires Igniter"
  end
end

defmodule Mix.Tasks.Amur.InstallProviderCredentialsTest do
  use Amur.Test.InstallHelpers, async: true

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
end

defmodule Mix.Tasks.Amur.InstallDotenvTest do
  use Amur.Test.InstallHelpers, async: true

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
end

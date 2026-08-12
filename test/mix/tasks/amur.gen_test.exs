defmodule Mix.Tasks.Amur.GenTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  setup do
    tmp = Path.join(System.tmp_dir!(), "amur_gen_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  defp run_in(tmp, args) do
    File.cd!(tmp, fn ->
      capture_io(fn -> Mix.Tasks.Amur.Gen.run(args) end)
    end)
  end

  test "generates config with every built-in provider with --all", %{tmp: tmp} do
    run_in(tmp, ["--all", "--app", "sample"])

    config = File.read!(Path.join(tmp, "config/runtime.exs"))

    for provider <- Amur.Config.built_in_providers() do
      env_prefix = provider |> Atom.to_string() |> String.upcase()

      assert config =~ "#{provider}: ["
      assert config =~ "System.fetch_env!(\"#{env_prefix}_CLIENT_ID\")"
      assert config =~ "System.fetch_env!(\"#{env_prefix}_CLIENT_SECRET\")"
    end

    # The generated config must be valid Elixir.
    assert {:ok, _} = Code.string_to_quoted(config)
  end

  test "defaults to a single github provider", %{tmp: tmp} do
    run_in(tmp, ["--app", "sample"])

    config = File.read!(Path.join(tmp, "config/runtime.exs"))

    assert config =~ "github: ["
    assert config =~ "System.fetch_env!(\"GITHUB_CLIENT_ID\")"
    refute config =~ "google: ["
    assert {:ok, _} = Code.string_to_quoted(config)
  end

  test "--provider and --all are mutually exclusive", %{tmp: tmp} do
    error =
      assert_raise Mix.Error, fn ->
        run_in(tmp, ["--all", "--provider", "google", "--app", "sample"])
      end

    assert error.message =~ "cannot be combined"
  end
end

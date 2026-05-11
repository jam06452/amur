defmodule Amur.ConfigTest do
  use ExUnit.Case, async: true

  setup do
    # Ensure clean env between tests
    on_exit(fn -> Application.delete_env(:amur, :providers) end)
    :ok
  end

  test "resolve/1 returns unknown for invalid string" do
    assert {:error, :unknown_provider} = Amur.Config.resolve("nope")
  end

  test "resolve/1 returns unknown for unconfigured atom" do
    Application.put_env(:amur, :providers, [])
    assert {:error, :unknown_provider} = Amur.Config.resolve(:github)
  end

  test "resolve/1 builds config when provider configured with credentials" do
    Application.put_env(:amur, :providers, github: [client_id: "id", client_secret: "sec"])

    assert {:ok, {module, config}} = Amur.Config.resolve(:github)
    assert module == Amur.Providers.GitHub
    assert config[:client_id] == "id"
    assert config[:client_secret] == "sec"
    assert config[:strategy] == module.strategy()
  end
end

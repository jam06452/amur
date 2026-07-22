defmodule Amur.Providers.AzureADTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.AzureAD

  test "strategy/0 returns the expected strategy module" do
    assert AzureAD.strategy() == Assent.Strategy.AzureAD
  end

  test "base_config/0 includes email profile scope and form_post response_mode" do
    config = AzureAD.base_config()

    assert Keyword.get(config, :authorization_params) == [
             scope: "email profile",
             response_mode: "form_post"
           ]

    assert Keyword.get(config, :client_authentication_method) == "client_secret_post"
  end

  test "normalize_user/1 returns normalized map" do
    user = %{
      "sub" => "123",
      "email" => "foo@example.com",
      "name" => "Foo",
      "picture" => "http://a"
    }

    normalized = AzureAD.normalize_user(user)

    assert normalized.uid == "123"
    assert normalized.email == "foo@example.com"
    assert normalized.name == "Foo"
    assert normalized.avatar == "http://a"
  end
end

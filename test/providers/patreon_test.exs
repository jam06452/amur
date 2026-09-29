defmodule Amur.Providers.PatreonTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.Patreon

  test "strategy/0 returns the expected strategy module" do
    assert Patreon.strategy() == Assent.Strategy.OAuth2
  end

  test "base_config/0 uses the v2 identity endpoint with explicit fields" do
    config = Patreon.base_config()

    assert Keyword.get(config, :base_url) == "https://www.patreon.com"
    assert Keyword.get(config, :authorize_url) == "/oauth2/authorize"
    assert Keyword.get(config, :token_url) == "/api/oauth2/token"

    assert Keyword.get(config, :user_url) ==
             "/api/oauth2/v2/identity?fields%5Buser%5D=email,full_name,thumb_url"

    assert Keyword.get(config, :auth_method) == :client_secret_post
  end

  test "base_config/0 includes the identity scopes" do
    assert Patreon.base_config() |> Keyword.get(:authorization_params) ==
             [scope: "identity identity[email]"]
  end

  test "normalize_user/1 unwraps the JSON:API data object" do
    user = %{
      "data" => %{
        "id" => "123456",
        "type" => "user",
        "attributes" => %{
          "email" => "foo@example.com",
          "full_name" => "Foo Bar",
          "thumb_url" => "https://c8.patreon.com/2/100/123456"
        }
      }
    }

    normalized = Patreon.normalize_user(user)

    assert normalized.uid == "123456"
    assert normalized.email == "foo@example.com"
    assert normalized.name == "Foo Bar"
    assert normalized.avatar == "https://c8.patreon.com/2/100/123456"
  end

  test "normalize_user/1 handles a missing data object" do
    normalized = Patreon.normalize_user(%{})

    assert normalized.uid == nil
    assert normalized.email == nil
    assert normalized.name == nil
    assert normalized.avatar == nil
  end
end

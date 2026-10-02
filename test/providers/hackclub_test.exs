defmodule Amur.Providers.HackClubTest do
  use ExUnit.Case, async: true

  alias Amur.Providers.HackClub

  test "uses OAuth2 and exposes Hack Club endpoints and auth settings" do
    config = HackClub.base_config()

    assert HackClub.strategy() == Assent.Strategy.OAuth2
    assert config[:base_url] == "https://auth.hackclub.com"
    assert config[:authorize_url] == "/oauth/authorize"
    assert config[:token_url] == "/oauth/token"
    assert config[:user_url] == "/api/v1/me"
    assert config[:auth_method] == :client_secret_post
    assert config[:authorization_params] == [scope: "email slack_id name"]
  end

  test "normalizes nested identity data" do
    normalized =
      HackClub.normalize_user(%{
        "identity" => %{
          "id" => "identity-1",
          "primary_email" => "person@example.com",
          "first_name" => "Ada",
          "last_name" => "Lovelace",
          "slack_id" => "U123"
        }
      })

    assert normalized == %{
             uid: "identity-1",
             email: "person@example.com",
             name: "Ada Lovelace",
             slack_id: "U123"
           }
  end

  test "preserves the provider's empty-name behavior for missing names" do
    assert HackClub.normalize_user(%{"identity" => %{"id" => "1"}}).name == " "
  end
end

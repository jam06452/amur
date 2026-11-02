defmodule Amur.ProviderExamplesTest do
  use ExUnit.Case, async: true

  test "custom provider examples authenticate their token requests" do
    {:docs_v1, _, _, _, %{"en" => provider_doc}, _, _} = Code.fetch_docs(Amur.Provider)

    module_example =
      Regex.scan(~r/^    (.*)$/m, provider_doc)
      |> Enum.map_join("\n", fn [_, line] -> line end)

    guide_examples =
      for path <- ["README.md", "guides/learning/custom_providers.md"],
          [_, code] <- Regex.scan(~r/```elixir\n(.*?)\n```/s, File.read!(path)),
          String.contains?(code, "use Amur.Provider"),
          do: code

    for {example, index} <- Enum.with_index([module_example | guide_examples]) do
      module = Module.concat(__MODULE__, "Example#{index}")

      # Supply deterministic credentials without changing the process environment.
      ast =
        example
        |> Code.string_to_quoted!()
        |> Macro.prewalk(fn
          {:defmodule, meta, [_name, body]} -> {:defmodule, meta, [module, body]}
          {{:., _, [{:__aliases__, _, [:System]}, :fetch_env!]}, _, [key]} -> key
          node -> node
        end)

      Code.compile_quoted(ast)

      config =
        module.base_config()
        |> Keyword.merge(
          redirect_uri: "https://app.example/auth/callback",
          session_params: %{state: "expected"},
          http_adapter: __MODULE__.HTTPAdapter
        )

      assert {:ok, _} =
               module.strategy().callback(config, %{"state" => "expected", "code" => "code"})

      assert_receive {:token_request, body}
      assert body["client_id"] == config[:client_id]
      assert body["client_secret"] == config[:client_secret]
    end
  end

  defmodule HTTPAdapter do
    @behaviour Assent.HTTPAdapter

    @impl true
    def request(:post, _url, body, _headers, _opts) do
      send(self(), {:token_request, URI.decode_query(body)})
      {:ok, %Assent.HTTPAdapter.HTTPResponse{status: 200, body: %{"access_token" => "token"}}}
    end

    def request(:get, _url, _body, _headers, _opts) do
      {:ok, %Assent.HTTPAdapter.HTTPResponse{status: 200, body: %{"id" => "user"}}}
    end
  end
end

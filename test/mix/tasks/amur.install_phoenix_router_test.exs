defmodule Mix.Tasks.Amur.InstallPhoenixRouterTest do
  use Amur.Test.InstallHelpers, async: true

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

  test "does not ask to remount an existing router when generation is skipped" do
    {:ok, _igniter, %{notices: notices}} =
      apply_install_with_messages(
        ["--app", "sample", "--page", "--no-router", "--yes"],
        %{
          "lib/sample_web/router.ex" => """
          defmodule SampleWeb.Router do
            use Phoenix.Router

            scope "/auth", alias: false do
              forward "/", Amur.Router
            end
          end
          """
        }
      )

    assert Enum.any?(notices, &String.contains?(&1, "Open the sign-in page at"))
    refute Enum.any?(notices, &String.contains?(&1, "Mount Amur.Router in your router"))
  end

  test "does not add a second forward when the router already mounts Amur" do
    mounted = """
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
    """

    igniter =
      apply_install(
        ["--app", "sample", "--no-config", "--no-controller", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",\s*Amur\.Router/, router)) == 1
  end

  test "does not mistake a quoted mount in another module for the selected router" do
    igniter =
      apply_install(
        ["--app", "sample", "--no-config", "--no-controller", "--yes"],
        %{
          "lib/sample_web/router.ex" => """
          defmodule SampleWeb.Router do
            use Phoenix.Router
          end

          defmodule SampleWeb.RouterHelpers do
            defmacro auth_routes do
              quote do
                scope "/auth", alias: false do
                  forward "/", Amur.Router
                end
              end
            end
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",\s*Amur\.Router/, router)) == 2
  end

  test "does not mistake a prefixed auth scope for the root mount" do
    igniter =
      apply_install(
        ["--app", "sample", "--no-config", "--no-controller", "--yes"],
        %{
          "lib/sample_web/router.ex" => """
          defmodule SampleWeb.Router do
            use Phoenix.Router

            scope "/admin", alias: false do
              scope "/auth", alias: false do
                forward "/", Amur.Router
              end
            end
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",\s*Amur\.Router/, router)) == 2
  end

  test "resolves aliases at the forward instead of declarations later in the module" do
    igniter =
      apply_install(
        ["--app", "sample", "--no-config", "--no-controller", "--yes"],
        %{
          "lib/sample_web/router.ex" => """
          defmodule SampleWeb.Router do
            use Phoenix.Router
            alias Amur.Router, as: AuthRouter

            scope "/auth", alias: false do
              forward "/", AuthRouter
            end

            alias Other.Router, as: AuthRouter
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",/, router)) == 1
  end

  test "does not mistake Phoenix controller aliasing for an Amur mount" do
    igniter =
      apply_install(
        ["--app", "sample", "--no-config", "--no-controller", "--yes"],
        %{
          "lib/sample_web/router.ex" => """
          defmodule SampleWeb.Router do
            use Phoenix.Router

            scope "/auth", SampleWeb do
              forward "/", Amur.Router
            end
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",\s*Amur\.Router/, router)) == 2
    assert router =~ ~s|scope "/auth", alias: false do|
  end

  test "does not treat a dynamic scope path or alias as a root Amur mount" do
    for scope <- ["path: @prefix, alias: false", "path: \"/\", alias: @web_module"] do
      igniter =
        apply_install(["--app", "sample", "--no-config", "--no-controller", "--yes"], %{
          "lib/sample_web/router.ex" => """
          defmodule SampleWeb.Router do
            use Phoenix.Router
            @prefix "/admin"
            @web_module SampleWeb
            scope #{scope} do
              forward "/auth", Amur.Router
            end
          end
          """
        })

      router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
      assert router =~ "scope \"/auth\", alias: false"
      assert router =~ "forward(\"/\", Amur.Router)"
    end
  end

  test "adds the /auth mount when Amur is forwarded at a different path" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/oauth", alias: false do
        pipe_through :browser
        forward "/", Amur.Router
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--no-config", "--no-controller", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert router =~ ~s|scope "/auth", alias: false do|
    assert length(Regex.scan(~r/forward\(?\s*"\/"\s*,\s*Amur\.Router/, router)) == 2
  end

  test "adds the /auth mount when Amur is only forwarded in a nested scope" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser

        scope "/nested", alias: false do
          forward "/", Amur.Router
        end
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--no-config", "--no-controller", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/"\s*,\s*Amur\.Router/, router)) == 2
  end

  test "recognizes an existing mount written through an alias" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router
      alias Amur.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", Router
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--no-config", "--no-controller", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",\s*Router/, router)) == 1
    refute router =~ ~s|forward("/", Amur.Router)|
  end

  test "adds the mount when the alias points at a different module" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router
      alias Other.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", Router
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--no-config", "--no-controller", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert router =~ ~s|forward("/", Amur.Router)|
  end

  test "adds the mount when the auth scope forwards a non-Amur router" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", Other.Router
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--no-config", "--no-controller", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert router =~ ~s|forward("/", Amur.Router)|
  end

  test "adds the mount when the auth scope forwards a different path" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/nested", Amur.Router
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--no-config", "--no-controller", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert router =~ ~s|forward("/", Amur.Router)|
  end

  test "warns when the detected Phoenix router cannot be located" do
    # `select_router/1` resolves the router through an alias, so it can name a
    # module that `find_module/2` cannot find. The installer must warn rather
    # than crash while trying to read the router's pipelines.
    {:ok, _igniter, %{warnings: warnings, notices: notices}} =
      apply_install_with_messages(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.NotARouter do\nend\n",
          "lib/weird/thing.ex" => """
          alias SampleWeb.Router

          defmodule Router do
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
      )

    assert Enum.any?(
             warnings,
             &String.contains?(
               &1,
               "Could not find the Phoenix router SampleWeb.Router to mount Amur.Router."
             )
           )

    # The next steps must not point the user at a route that was never mounted.
    assert Enum.any?(notices, &String.contains?(&1, "Mount Amur.Router in your router"))
    refute Enum.any?(notices, &String.contains?(&1, "Open the sign-in page at"))
    refute Enum.any?(notices, &String.contains?(&1, "Initiate an OAuth flow at"))
  end

  test "warns when the Phoenix router cannot be located" do
    # `list_routers/1` scans every Elixir source, but `find_module/2` skips
    # `_test.exs` files, so a router defined there is selected yet cannot be
    # patched. The installer must warn rather than crash in `has_pipeline/3`.
    router = """
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

    {:ok, igniter, %{warnings: warnings}} =
      apply_install_with_messages(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Placeholder do\nend\n",
          "lib/sample_web/router_test.exs" => router
        }
      )

    assert Enum.any?(
             warnings,
             &String.contains?(&1, "Could not find the Phoenix router SampleWeb.Router")
           )

    assert igniter.assigns[:test_files]["lib/sample_web/router_test.exs"] =~ "use Phoenix.Router"
  end

  test "recognizes pathless scopes and explicitly nil scope aliases" do
    for scope <- ["alias: false", ~s("/auth", alias: nil)] do
      path = if scope == "alias: false", do: "/auth", else: "/"

      source = """
      defmodule SampleWeb.Router do
        use Phoenix.Router
        scope #{scope} do
          forward "#{path}", Amur.Router
        end
      end
      """

      igniter =
        apply_install(["--app", "sample", "--no-config", "--no-controller", "--yes"], %{
          "lib/sample_web/router.ex" => source
        })

      result = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
      assert length(Regex.scan(~r/forward/, result)) == 1
    end
  end

  test "a scope without settings does not count as a known mount" do
    source = """
    defmodule SampleWeb.Router do
      use Phoenix.Router
      scope do
        forward "/auth", Amur.Router
      end
    end
    """

    igniter =
      apply_install(["--app", "sample", "--no-config", "--no-controller", "--yes"], %{
        "lib/sample_web/router.ex" => source
      })

    result = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert result =~ ~s(scope "/auth", alias: false)
  end

  test "--no-router tolerates a router placeholder without a do block" do
    source = """
    defmodule SampleWeb.Router, [use(Phoenix.Router)]
    """

    {:ok, igniter, %{notices: notices}} =
      apply_install_with_messages(["--app", "sample", "--no-router", "--yes"], %{
        "lib/sample_web/router.ex" => source,
        "test/router_test.exs" => """
        defmodule SampleWeb.Router do
          use Phoenix.Router
        end
        """
      })

    refute igniter.assigns[:test_files]["lib/sample_web/router.ex"] =~ "forward"
    assert Enum.any?(notices, &String.contains?(&1, "Mount Amur.Router"))
  end

  test "recognizes an alias declared with an atom `as:` name" do
    mounted = """
    defmodule SampleWeb.Router do
      use Phoenix.Router
      alias Amur.Router, as: :AmurAuth

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", AmurAuth
      end
    end
    """

    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{"lib/sample_web/router.ex" => mounted}
      )

    router = igniter.assigns[:test_files]["lib/sample_web/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/",\s*AmurAuth/, router)) == 1
  end
end

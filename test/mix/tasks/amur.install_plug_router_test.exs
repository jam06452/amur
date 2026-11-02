defmodule Mix.Tasks.Amur.InstallPlugRouterTest do
  use Amur.Test.InstallHelpers, async: true

  test "patches a standalone Plug router with an auth forward" do
    igniter =
      apply_install(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router
            plug :match
            plug :dispatch
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert router =~ ~s|forward("/auth", to: Amur.Router)|
  end

  test "does not duplicate an existing standalone auth forward" do
    igniter =
      apply_install(
        ["--app", "sample", "--no-config", "--no-controller", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router
            forward("/auth", to: Amur.Router)
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert length(Regex.scan(~r/forward\(\"\/auth\"[^\n]*Amur\.Router/, router)) == 1
  end

  test "warns when no standalone Plug router can be found" do
    {:ok, _igniter, %{warnings: warnings}} =
      apply_install_with_messages(
        ["--app", "sample", "--no-controller", "--no-config", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample.ex" => "defmodule Sample do\nend\n"
        }
      )

    assert Enum.any?(
             warnings,
             &String.contains?(&1, "Could not find a Plug.Router module to patch.")
           )
  end

  test "does not point at an unmounted route when no Plug router can be found" do
    # With config generation enabled the next steps reach the flow step. Since no
    # Plug.Router was patched, the user must be told to mount Amur.Router rather
    # than pointed at a route that was never mounted. The controller is supplied
    # so config generation is permitted without `--no-controller`.
    {:ok, _igniter, %{notices: notices}} =
      apply_install_with_messages(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample.ex" => "defmodule Sample do\nend\n",
          "lib/sample_web/controllers/auth_controller.ex" =>
            "defmodule SampleWeb.AuthController do\nend\n"
        }
      )

    assert Enum.any?(notices, &String.contains?(&1, "Mount Amur.Router in your router"))
    refute Enum.any?(notices, &String.contains?(&1, "Initiate an OAuth flow at"))
    refute Enum.any?(notices, &String.contains?(&1, "Open the sign-in page at"))
  end

  test "warns when an aliased standalone Plug router cannot be located" do
    {:ok, _igniter, %{warnings: warnings, notices: notices}} =
      apply_install_with_messages(
        ["--app", "sample", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/weird/thing.ex" => """
          alias Sample.Router

          defmodule Router do
            use Plug.Router
            plug :match
            plug :dispatch
          end
          """
        }
      )

    assert Enum.any?(
             warnings,
             &String.contains?(&1, "Could not find the Plug router Sample.Router")
           )

    assert Enum.any?(notices, &String.contains?(&1, "Mount Amur.Router in your router"))
    refute Enum.any?(notices, &String.contains?(&1, "Initiate an OAuth flow at"))
  end

  test "patches a Plug router that has no dispatch plug" do
    igniter =
      apply_install(
        ["--app", "sample", "--no-config", "--no-controller", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router
            plug :match
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert router =~ ~s|forward("/auth", to: Amur.Router)|
  end

  test "patches a Plug router that has no plug calls at all" do
    igniter =
      apply_install(
        ["--app", "sample", "--no-config", "--no-controller", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router

            def hello, do: :world
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert router =~ ~s|forward("/auth", to: Amur.Router)|
  end

  test "leaves a Plug router untouched when it has no use Plug.Router" do
    igniter =
      apply_install(
        ["--app", "sample", "--no-config", "--no-controller", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            plug :match
            plug :dispatch
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    refute router =~ "forward"
  end

  test "does not duplicate an existing Plug router forward written as an alias" do
    igniter =
      apply_install(
        ["--app", "sample", "--no-config", "--no-controller", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router
            alias Amur.Router
            plug :match
            plug :dispatch
            forward("/auth", to: Router)
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/auth"/, router)) == 1
  end

  test "does not duplicate an existing Plug router forward written as an alias list" do
    igniter =
      apply_install(
        ["--app", "sample", "--no-config", "--no-controller", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router
            plug :match
            plug :dispatch
            forward("/auth", to: Amur.Router)
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert length(Regex.scan(~r/forward\(?\s*"\/auth"/, router)) == 1
  end

  test "adds a Plug router forward when the existing one points elsewhere" do
    igniter =
      apply_install(
        ["--app", "sample", "--no-config", "--no-controller", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router
            plug :match
            plug :dispatch
            forward("/other", to: Other.Router)
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert router =~ ~s|forward("/auth", to: Amur.Router)|
  end

  test "leaves a module without use Plug.Router untouched" do
    igniter =
      apply_install(
        ["--app", "sample", "--no-config", "--no-controller", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/not_a_router.ex" => """
          defmodule Sample.NotARouter do
            plug :match
            plug :dispatch
          end
          """
        }
      )

    source = igniter.assigns[:test_files]["lib/sample/not_a_router.ex"]
    refute source =~ "forward"
  end

  test "adds the mount when the router module cannot be found" do
    igniter =
      apply_install(
        ["--app", "sample", "--no-config", "--no-controller", "--yes"],
        %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Router do\nend\n",
          "lib/sample/router.ex" => """
          defmodule Sample.Router do
            use Plug.Router
            plug :match
            plug :dispatch
          end
          """
        }
      )

    router = igniter.assigns[:test_files]["lib/sample/router.ex"]
    assert router =~ ~s|forward("/auth", to: Amur.Router)|
  end

  test "--no-router reports whether a Plug router already mounts Amur" do
    for mounted? <- [true, false] do
      forward = if mounted?, do: ~s(forward "/auth", to: Amur.Router), else: ""

      source = """
      defmodule Sample.Router do
        use Plug.Router
        plug :match
        #{forward}
        plug :dispatch
      end
      """

      {:ok, igniter, %{notices: notices}} =
        apply_install_with_messages(["--app", "sample", "--no-router", "--yes"], %{
          "lib/sample_web/router.ex" => "defmodule SampleWeb.Placeholder do
end",
          "lib/sample/router.ex" => source
        })

      result = igniter.assigns[:test_files]["lib/sample/router.ex"]
      assert result =~ "forward" == mounted?
      assert Enum.any?(notices, &String.contains?(&1, "Initiate an OAuth flow at")) == mounted?
      assert Enum.any?(notices, &String.contains?(&1, "Mount Amur.Router")) == not mounted?
    end
  end
end

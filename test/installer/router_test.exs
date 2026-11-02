defmodule Amur.Installer.RouterTest do
  use ExUnit.Case, async: true

  alias Amur.Installer.Router
  alias Igniter.Code.{Common, Module}
  alias Sourceror.Zipper

  # Parse only the router fixture. The installer integration tests cover edits,
  # warnings and idempotency; these cases exercise lexical mount detection.
  defp mounted?(source, kind) do
    zipper = source |> Sourceror.parse_string!() |> Zipper.zip()
    {:ok, zipper} = Module.move_to_defmodule(zipper)
    {:ok, zipper} = Common.move_to_do_block(zipper)
    Router.mounted?(zipper, kind)
  end

  test "recognizes a forward that disables Phoenix aliasing on the route itself" do
    source = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      scope "/auth", SampleWeb do
        forward "/", Amur.Router, [], alias: false
      end
    end
    """

    assert mounted?(source, :phoenix)
  end

  test "recognizes an existing mount written through an `as:` alias" do
    source = """
    defmodule SampleWeb.Router do
      use Phoenix.Router
      alias Amur.Router, as: AmurAuth

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", AmurAuth
      end
    end
    """

    assert mounted?(source, :phoenix)
  end

  test "recognizes an existing mount written as a fully qualified Elixir alias" do
    source = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", Elixir.Amur.Router
      end
    end
    """

    assert mounted?(source, :phoenix)
  end

  test "ignores an alias whose target is not a module alias" do
    source = """
    defmodule SampleWeb.Router do
      use Phoenix.Router
      alias __MODULE__

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", Amur.Router
      end
    end
    """

    assert mounted?(source, :phoenix)
  end

  test "recognizes a mount written as a bare module argument" do
    source = """
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

    assert mounted?(source, :phoenix)
  end

  test "recognizes a mount when another scope precedes the auth scope" do
    source = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/", SampleWeb do
        pipe_through :browser
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", Amur.Router
      end
    end
    """

    assert mounted?(source, :phoenix)
  end

  test "ignores a forward whose path is not a literal string" do
    source = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward @path, Amur.Router
      end
    end
    """

    refute mounted?(source, :phoenix)
  end

  test "ignores a Phoenix forward whose target is a variable" do
    source = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", router
      end
    end
    """

    refute mounted?(source, :phoenix)
  end

  test "ignores a Phoenix forward whose target is a non-module literal" do
    source = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", "not a module"
      end
    end
    """

    refute mounted?(source, :phoenix)
  end

  test "ignores an alias whose target is a variable" do
    source = """
    defmodule SampleWeb.Router do
      use Phoenix.Router
      alias unquote(Some.Module)

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", Amur.Router
      end
    end
    """

    assert mounted?(source, :phoenix)
  end

  test "ignores an alias with an `as:` value that is not a name" do
    source = """
    defmodule SampleWeb.Router do
      use Phoenix.Router
      alias Amur.Router, as: unquote(:AmurAuth)

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", Amur.Router
      end
    end
    """

    assert mounted?(source, :phoenix)
  end

  test "ignores an alias option that is not `as:`" do
    source = """
    defmodule SampleWeb.Router do
      use Phoenix.Router
      alias Amur.Router, warn: false

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        pipe_through :browser
        forward "/", Amur.Router
      end
    end
    """

    assert mounted?(source, :phoenix)
  end

  test "recognizes a mount in a scope declared without options" do
    source = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth" do
        pipe_through :browser
        forward "/", Amur.Router
      end
    end
    """

    assert mounted?(source, :phoenix)
  end

  test "recognizes a mount in a scope whose body is a single statement" do
    source = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false do
        forward "/", Amur.Router
      end
    end
    """

    assert mounted?(source, :phoenix)
  end

  test "ignores a scope whose body is not a do block" do
    source = """
    defmodule SampleWeb.Router do
      use Phoenix.Router

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/auth", alias: false, do: :nothing
    end
    """

    refute mounted?(source, :phoenix)
  end

  test "recognizes a Plug router forward written as a bare module argument" do
    source = """
    defmodule Sample.Router do
      use Plug.Router
      plug :match
      plug :dispatch
      forward "/auth", Amur.Router
    end
    """

    assert mounted?(source, :plug)
  end

  test "ignores a Plug router forward whose path is not a literal string" do
    source = """
    defmodule Sample.Router do
      use Plug.Router
      plug :match
      plug :dispatch
      forward @path, Amur.Router
    end
    """

    refute mounted?(source, :plug)
  end

  test "ignores a Plug router forward with a non-module target" do
    source = """
    defmodule Sample.Router do
      use Plug.Router
      plug :match
      plug :dispatch
      forward "/auth", @router
    end
    """

    refute mounted?(source, :plug)
  end

  test "ignores a Plug router forward with an unrelated arity" do
    source = """
    defmodule Sample.Router do
      use Plug.Router
      plug :match
      plug :dispatch
      forward "/auth"
    end
    """

    refute mounted?(source, :plug)
  end

  test "ignores a Plug router forward with a non-keyword second argument" do
    source = """
    defmodule Sample.Router do
      use Plug.Router
      plug :match
      plug :dispatch
      forward "/auth", ["not", "a", "keyword"]
    end
    """

    refute mounted?(source, :plug)
  end

  test "ignores a Plug router forward whose target is a variable" do
    source = """
    defmodule Sample.Router do
      use Plug.Router
      plug :match
      plug :dispatch
      forward "/auth", to: router
    end
    """

    refute mounted?(source, :plug)
  end

  test "ignores a Plug router forward whose target is a bare atom" do
    source = """
    defmodule Sample.Router do
      use Plug.Router
      plug :match
      plug :dispatch
      forward "/auth", :not_a_module
    end
    """

    refute mounted?(source, :plug)
  end

  test "ignores a Plug router forward with a `to:` list that has no `to:` key" do
    source = """
    defmodule Sample.Router do
      use Plug.Router
      plug :match
      plug :dispatch
      forward "/auth", to: Amur.Router, host: "example.com"
    end
    """

    assert mounted?(source, :plug)
  end

  test "ignores a Plug router forward with a non-`to` option before `to:`" do
    source = """
    defmodule Sample.Router do
      use Plug.Router
      plug :match
      plug :dispatch
      forward "/auth", host: "example.com", to: Amur.Router
    end
    """

    assert mounted?(source, :plug)
  end

  test "ignores a Plug router forward with a non-keyword list second argument" do
    source = """
    defmodule Sample.Router do
      use Plug.Router
      plug :match
      plug :dispatch
      forward "/auth", ["not", "keyword"]
    end
    """

    refute mounted?(source, :plug)
  end
end

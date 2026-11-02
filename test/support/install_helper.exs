defmodule Amur.Test.InstallHelpers do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      import Amur.Test.InstallHelpers
    end
  end

  setup_all do
    {:ok, install_project: project()}
  end

  setup %{install_project: project} do
    # Each test receives its own immutable copy, including tests that install
    # multiple times. No writes are shared between tests or fixture variants.
    Process.put({__MODULE__, :project}, project)
    :ok
  end

  def apply_install(args, files \\ %{}) do
    {:ok, igniter, _messages} = apply_install_with_messages(args, files)
    igniter
  end

  def apply_install_with_messages(args, files) do
    project = Process.get({__MODULE__, :project})

    project
    |> Igniter.assign(:test_files, Map.merge(project.assigns.test_files, files))
    |> Map.update!(:rewrite, &Rewrite.drop(&1, Map.keys(files)))
    |> Igniter.include_glob("**/*.*")
    |> Igniter.compose_task("amur.install", args)
    |> Igniter.Test.apply_igniter()
  end

  defp project do
    default_files = %{
      "lib/sample_web.ex" => """
      defmodule SampleWeb do
        def controller do
          quote do
            use Phoenix.Controller, namespace: SampleWeb
          end
        end
      end
      """,
      "lib/sample_web/router.ex" => """
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
    }

    Igniter.Test.test_project(files: default_files)
  end
end

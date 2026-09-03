defmodule Mix.Tasks.Amur.Install do
  @shortdoc "Generates Amur auth boilerplate (router mount, AuthController, config)"
  @moduledoc """
  Generates the boilerplate needed to start using Amur in your application.

  Supports both Phoenix applications and standalone Plug.Router setups.
  """
  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :amur,
      schema: [
        provider: :string,
        app: :string,
        all: :boolean,
        config: :boolean,
        router: :boolean,
        controller: :boolean
      ],
      aliases: [
        p: :provider
      ]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    opts = igniter.args.options

    if opts[:all] && opts[:provider] do
      Mix.raise(
        "--provider and --all cannot be combined. " <>
          "Use --all to configure every built-in provider, " <>
          "or --provider <name> for a single one."
      )
    end

    app_name =
      case opts[:app] do
        nil -> Igniter.Project.Application.app_name(igniter)
        custom_app -> String.to_atom(custom_app)
      end

    {igniter, phoenix?, router} = detect_phoenix(igniter)
    {igniter, web_module} = resolve_web_module(igniter, app_name, opts, phoenix?, router)

    providers = resolve_providers(opts)
    validate_controller_options!(igniter, opts, web_module)

    igniter
    |> maybe_add_controller(opts, web_module, phoenix?)
    |> maybe_add_router(opts, phoenix?, router)
    |> maybe_add_config(opts, web_module, providers, phoenix?)
    |> queue_next_steps(web_module, providers, opts)
  end

  defp detect_phoenix(igniter) do
    case Igniter.Libs.Phoenix.select_router(igniter) do
      {igniter, nil} -> {igniter, false, nil}
      {igniter, router} -> {igniter, true, router}
    end
  end

  defp resolve_web_module(igniter, app_name, opts, true, _router) do
    if opts[:app] do
      {igniter, Module.concat([Macro.camelize(to_string(app_name)) <> "Web"])}
    else
      case Igniter.Libs.Phoenix.web_module(igniter) do
        {igniter, mod} when is_atom(mod) -> {igniter, mod}
        mod when is_atom(mod) -> {igniter, mod}
      end
    end
  end

  defp resolve_web_module(igniter, app_name, _opts, false, _router) do
    {igniter, Module.concat([Macro.camelize(to_string(app_name))])}
  end

  defp resolve_providers(opts) do
    cond do
      opts[:all] && amur_config_built_in_providers?() ->
        Amur.Config.built_in_providers()

      opts[:all] ->
        Mix.raise("Amur.Config.built_in_providers/0 is unavailable; cannot resolve --all.")

      not is_nil(opts[:provider]) ->
        [parse_provider!(opts[:provider])]

      true ->
        [:github]
    end
  end

  defp parse_provider!(provider) do
    if Regex.match?(~r/^[a-z][a-z0-9_]*$/, provider) do
      provider = String.to_atom(provider)

      if not amur_config_built_in_providers?() or
           provider in Amur.Config.built_in_providers() do
        provider
      else
        Mix.raise("Unknown built-in provider #{inspect(provider)}.")
      end
    else
      Mix.raise(
        "Invalid provider #{inspect(provider)}. Provider names must start with a lowercase letter " <>
          "and contain only lowercase letters, numbers, and underscores."
      )
    end
  end

  defp amur_config_built_in_providers? do
    Code.ensure_loaded?(Amur.Config) &&
      function_exported?(Amur.Config, :built_in_providers, 0)
  end

  defp maybe_add_controller(igniter, opts, web_module, phoenix?) do
    if opts[:controller] == false do
      igniter
    else
      add_controller(igniter, web_module, phoenix?)
    end
  end

  defp validate_controller_options!(igniter, opts, web_module) do
    if opts[:controller] == false && opts[:config] != false do
      controller_module = Module.concat([web_module, AuthController])
      target_path = Igniter.Project.Module.proper_location(igniter, controller_module)

      unless Igniter.exists?(igniter, target_path) do
        Mix.raise(
          "--no-controller cannot be combined with config generation unless " <>
            "#{inspect(controller_module)} already exists or --no-config is also supplied."
        )
      end
    end
  end

  defp add_controller(igniter, web_module, phoenix?) do
    controller_module = Module.concat([web_module, AuthController])
    target_path = Igniter.Project.Module.proper_location(igniter, controller_module)

    if Igniter.exists?(igniter, target_path) do
      Igniter.add_notice(igniter, "[skip] #{target_path} already exists; leaving unchanged.")
    else
      contents = controller_contents(web_module, phoenix?)
      Igniter.create_new_file(igniter, target_path, contents)
    end
  end

  defp controller_contents(web_module, true) do
    """
    defmodule #{inspect(web_module)}.AuthController do
      use #{inspect(web_module)}, :controller

      def on_success(conn, %{user: user}) do
        conn
        |> put_flash(:info, "Logged in as \#{user[:email]}")
        |> redirect(to: ~p"/")
        |> halt()
      end

      def on_failure(conn, _reason) do
        conn
        |> put_flash(:error, "Authentication failed.")
        |> redirect(to: ~p"/")
        |> halt()
      end
    end
    """
  end

  defp controller_contents(web_module, false) do
    """
    defmodule #{inspect(web_module)}.AuthController do
      import Plug.Conn

      def on_success(conn, %{user: _user}) do
        redirect(conn, "/")
      end

      def on_failure(conn, _reason) do
        redirect(conn, "/")
      end

      defp redirect(conn, to) do
        conn
        |> put_resp_header("location", to)
        |> send_resp(302, "")
        |> halt()
      end
    end
    """
  end

  defp maybe_add_router(igniter, opts, phoenix?, router) do
    if opts[:router] == false do
      igniter
    else
      add_router(igniter, phoenix?, router)
    end
  end

  defp add_router(igniter, true, router) do
    {igniter, has_browser_pipeline?} =
      Igniter.Libs.Phoenix.has_pipeline(igniter, router, :browser)

    contents =
      if has_browser_pipeline? do
        """
        pipe_through :browser
        forward "/", Amur.Router
        """
      else
        "forward \"/\", Amur.Router"
      end

    Igniter.Libs.Phoenix.add_scope(
      igniter,
      "/auth",
      contents,
      router: router,
      arg2: [alias: false]
    )
  end

  defp add_router(igniter, false, _router) do
    igniter = Igniter.include_all_elixir_files(igniter)

    {igniter, modules} =
      Igniter.Project.Module.find_all_matching_modules(igniter, fn _module, zipper ->
        match?({:ok, _}, Igniter.Code.Module.move_to_use(zipper, Plug.Router))
      end)

    case modules do
      [module | _] ->
        Igniter.Project.Module.find_and_update_module!(
          igniter,
          module,
          &update_plug_router/1
        )

      [] ->
        Igniter.add_warning(igniter, "Could not find a Plug.Router module to patch.")
    end
  end

  defp update_plug_router(zipper) do
    if has_auth_forward?(zipper) do
      {:ok, zipper}
    else
      {:ok, patch_plug_router_zipper(zipper)}
    end
  end

  defp has_auth_forward?(zipper) do
    match?(
      {:ok, _},
      Igniter.Code.Function.move_to_function_call(zipper, :forward, 2, fn call ->
        auth_forward_call?(Sourceror.Zipper.node(call))
      end)
    )
  end

  defp auth_forward_call?({:forward, _, ["/auth", router]}), do: amur_router_ast?(router)
  defp auth_forward_call?(_), do: false

  defp amur_router_ast?(Amur.Router), do: true
  defp amur_router_ast?({:__aliases__, _, [:Amur, :Router]}), do: true
  defp amur_router_ast?(to: router), do: amur_router_ast?(router)
  defp amur_router_ast?(_), do: false

  defp patch_plug_router_zipper(zipper) do
    dispatch_call =
      Igniter.Code.Function.move_to_function_call(zipper, :plug, [1, 2], fn call ->
        match?({:plug, _, [:dispatch | _]}, Sourceror.Zipper.node(call))
      end)

    forward_ast = Sourceror.parse_string!("forward(\"/auth\", to: Amur.Router)")

    case dispatch_call do
      {:ok, call_zipper} ->
        Sourceror.Zipper.insert_left(call_zipper, forward_ast)

      _ ->
        case Igniter.Code.Module.move_to_use(zipper, Plug.Router) do
          {:ok, use_zipper} ->
            Sourceror.Zipper.insert_right(use_zipper, forward_ast)

          _ ->
            zipper
        end
    end
  end

  defp maybe_add_config(igniter, opts, web_module, providers, phoenix?) do
    if opts[:config] == false do
      igniter
    else
      add_config(igniter, web_module, providers, phoenix?, opts[:controller] != false)
    end
  end

  defp add_config(igniter, web_module, providers, _phoenix?, controller?) do
    base_url_expr = "System.get_env(\"BASE_URL\") || \"http://localhost:4000\""

    providers_code = providers_config_code(providers)

    igniter
    |> Igniter.Project.Config.configure(
      "runtime.exs",
      :amur,
      [:base_url],
      {:code, Sourceror.parse_string!(base_url_expr)}
    )
    |> Igniter.Project.Config.configure(
      "runtime.exs",
      :amur,
      [:providers],
      {:code, Sourceror.parse_string!("[\n    #{providers_code}\n  ]")}
    )
    |> maybe_configure_callbacks(web_module, controller?)
    |> add_dotenv_loader()
  end

  defp add_dotenv_loader(igniter) do
    Igniter.update_elixir_file(igniter, "config/runtime.exs", fn zipper ->
      source = zipper |> Sourceror.Zipper.topmost() |> Sourceror.Zipper.node()

      if dotenv_loader_present?(source) do
        {:ok, zipper}
      else
        case Igniter.Code.Function.move_to_function_call_in_current_scope(
               zipper,
               :import,
               1,
               fn call ->
                 Igniter.Code.Function.argument_matches_predicate?(
                   call,
                   0,
                   &Igniter.Code.Common.nodes_equal?(&1, Config)
                 )
               end
             ) do
          {:ok, import_zipper} ->
            {:ok, Igniter.Code.Common.add_code(import_zipper, dotenv_loader())}

          :error ->
            {:ok, Igniter.Code.Common.add_code(zipper, dotenv_loader(), placement: :before)}
        end
      end
    end)
  end

  defp dotenv_loader_present?(source) do
    rendered_source = Sourceror.to_string(source)

    String.contains?(rendered_source, "File.exists?(\".env\")") and
      String.contains?(rendered_source, "System.put_env(key, val)")
  end

  defp dotenv_loader do
    """
    if Mix.env() != :test and File.exists?(".env") do
      ".env"
      |> File.read!()
      |> String.split("\\n", trim: true)
      |> Enum.reject(&(String.starts_with?(&1, "#") or &1 == ""))
      |> Enum.each(fn line ->
        case String.split(line, "=", parts: 2) do
          [key, val] ->
            key = String.trim(key)
            val = val |> String.trim() |> String.trim("\\"")
            System.put_env(key, val)

          _ ->
            :ok
        end
      end)
    end
    """
  end

  defp maybe_configure_callbacks(igniter, _web_module, false), do: igniter

  defp maybe_configure_callbacks(igniter, web_module, true) do
    igniter
    |> Igniter.Project.Config.configure(
      "runtime.exs",
      :amur,
      [:on_success],
      {:code, Sourceror.parse_string!("&#{inspect(web_module)}.AuthController.on_success/2")}
    )
    |> Igniter.Project.Config.configure(
      "runtime.exs",
      :amur,
      [:on_failure],
      {:code, Sourceror.parse_string!("&#{inspect(web_module)}.AuthController.on_failure/2")}
    )
  end

  defp providers_config_code(providers) do
    Enum.map_join(providers, ",\n    ", fn provider ->
      env = provider |> Atom.to_string() |> String.upcase()

      """
      #{provider}: [
        client_id: System.fetch_env!("#{env}_CLIENT_ID"),
        client_secret: System.fetch_env!("#{env}_CLIENT_SECRET")
      ]
      """
      |> String.trim()
    end)
  end

  defp queue_next_steps(igniter, web_module, providers, opts) do
    provider_example = List.first(providers, :github)

    next_steps =
      if opts[:config] == false do
        "    No runtime configuration was generated."
      else
        env_keys =
          providers
          |> Enum.flat_map(fn p ->
            prefix = p |> Atom.to_string() |> String.upcase()
            ["#{prefix}_CLIENT_ID", "#{prefix}_CLIENT_SECRET"]
          end)
          |> Enum.join(", ")

        controller_step =
          if opts[:controller] == false do
            "      2. Verify the existing #{inspect(web_module)}.AuthController callbacks."
          else
            "      2. Customize auth success/failure handling:\n         #{inspect(web_module)}.AuthController"
          end

        """
            Required next steps:
              1. Export the following environment variables:
                 #{env_keys}

        #{controller_step}

              3. Initiate an OAuth flow at:
                 /auth/#{provider_example}
        """
      end

    status =
      if opts[:config] == false do
        "Amur boilerplate generated."
      else
        "Amur configured successfully."
      end

    notice = """
    #{status}

    #{next_steps}
    """

    Igniter.add_notice(igniter, notice)
  end
end

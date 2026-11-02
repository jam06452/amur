if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Amur.Install do
    @shortdoc "Generates Amur auth boilerplate (router mount, AuthController, config)"
    @moduledoc """
    Generates the boilerplate needed to start using Amur in your application.

    Supports both Phoenix applications and standalone Plug.Router setups.
    Unlike the legacy `mix amur.gen` task, this Igniter task edits project
    source and configuration through Igniter's AST-aware operations.
    """
    use Igniter.Mix.Task

    alias Igniter.Code.{Common, Function}
    alias Igniter.Code.Keyword, as: CodeKeyword
    alias Igniter.Code.Module, as: CodeModule
    alias Igniter.Libs.Phoenix
    alias Igniter.Project.Application
    alias Igniter.Project.Config, as: ProjectConfig
    alias Igniter.Project.Module, as: ProjectModule
    alias Sourceror.Zipper

    @doc """
    Describes the options accepted by `mix igniter.install amur`.

    The returned schema lets Igniter expose provider, application, and
    component-generation options consistently with the task implementation.
    """
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
          controller: :boolean,
          page: :boolean
        ],
        aliases: [
          p: :provider
        ]
      }
    end

    @doc """
    Applies Amur's generated controller, router, and runtime configuration.

    Existing files and configuration are preserved where possible. The
    `--provider` and `--all` options are mutually exclusive, and generated
    callbacks are wired only when a controller is requested. Multiple providers
    can be passed to `--provider` as a comma-separated list.

    Passing `--page` also configures the application name used by the built-in
    sign-in page, which `Amur.Router` serves at the mount point (`GET /auth`).
    """
    @impl Igniter.Mix.Task
    def igniter(igniter) do
      opts = igniter.args.options

      if opts[:all] && opts[:provider] do
        Mix.raise(
          "--provider and --all cannot be combined. " <>
            "Use --all to configure every built-in provider, " <>
            "or --provider <name>[,<name>...] for one or more providers."
        )
      end

      app_name =
        case opts[:app] do
          nil -> Application.app_name(igniter)
          custom_app -> String.to_atom(custom_app)
        end

      {igniter, phoenix?, router} = detect_phoenix(igniter)
      {igniter, web_module} = resolve_web_module(igniter, app_name, opts, phoenix?, router)

      providers = resolve_providers(opts)
      validate_controller_options!(igniter, opts, web_module)

      {igniter, router_status} =
        igniter
        |> maybe_add_controller(opts, web_module, phoenix?)
        |> maybe_add_router(opts, phoenix?, router)

      igniter
      |> maybe_add_config(opts, web_module, providers, phoenix?)
      |> maybe_add_page(opts, app_name)
      |> queue_next_steps(web_module, providers, opts, router_status)
    end

    defp detect_phoenix(igniter) do
      case Phoenix.select_router(igniter) do
        {igniter, nil} -> {igniter, false, nil}
        {igniter, router} -> {igniter, true, router}
      end
    end

    defp resolve_web_module(igniter, app_name, opts, true, _router) do
      if opts[:app] do
        {igniter, Module.concat([Macro.camelize(to_string(app_name)) <> "Web"])}
      else
        {igniter, Phoenix.web_module(igniter)}
      end
    end

    defp resolve_web_module(igniter, app_name, _opts, false, _router) do
      {igniter, Module.concat([Macro.camelize(to_string(app_name))])}
    end

    defp resolve_providers(opts) do
      cond do
        opts[:all] ->
          Amur.Config.built_in_providers()

        not is_nil(opts[:provider]) ->
          opts[:provider]
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.map(&parse_provider!/1)
          |> Enum.uniq()

        true ->
          [:github]
      end
    end

    defp parse_provider!(provider) do
      if Regex.match?(~r/^[a-z][a-z0-9_]*$/, provider) do
        provider = String.to_atom(provider)

        if provider in Amur.Config.built_in_providers() do
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

    defp maybe_add_controller(igniter, opts, web_module, phoenix?) do
      if opts[:controller] == false do
        igniter
      else
        add_controller(igniter, web_module, phoenix?)
      end
    end

    defp validate_controller_options!(igniter, opts, web_module) do
      if opts[:controller] == false && opts[:config] != false && not page_only?(opts) do
        controller_module = Module.concat([web_module, AuthController])

        unless controller_exists?(igniter, controller_module, web_module) do
          Mix.raise(
            "--no-controller cannot be combined with config generation unless " <>
              "#{inspect(controller_module)} already exists or --no-config is also supplied."
          )
        end
      end
    end

    # The controller may live at the path this task generates or anywhere else the
    # project chose, so both are checked before refusing to wire the callbacks.
    defp controller_exists?(igniter, controller_module, web_module) do
      Igniter.exists?(igniter, controller_path(web_module, true)) or
        match?({:ok, _}, ProjectModule.find_module(igniter, controller_module))
    end

    defp add_controller(igniter, web_module, phoenix?) do
      target_path = controller_path(web_module, phoenix?)
      igniter = prevent_controller_relocation(igniter, target_path)

      if Igniter.exists?(igniter, target_path) do
        Igniter.add_notice(igniter, "[skip] #{target_path} already exists; leaving unchanged.")
      else
        contents = controller_contents(web_module, phoenix?)
        Igniter.create_new_file(igniter, target_path, contents, format?: false)
      end
    end

    defp controller_path(web_module, _phoenix?) do
      web_root = web_module |> Module.split() |> hd() |> Macro.underscore()
      "lib/#{web_root}/controllers/auth_controller.ex"
    end

    defp prevent_controller_relocation(igniter, target_path) do
      igniter_exs = igniter.assigns[:igniter_exs] || %{}
      dont_move_files = Keyword.get(igniter_exs, :dont_move_files, [])

      Igniter.assign(
        igniter,
        :igniter_exs,
        Keyword.put(igniter_exs, :dont_move_files, Enum.uniq([target_path | dont_move_files]))
      )
    end

    defp controller_contents(web_module, true) do
      """
      defmodule #{inspect(web_module)}.AuthController do
        use #{inspect(web_module)}, :controller

        @behaviour Amur.Callback

        @impl true
        def on_success(conn, %{user: user}) do
          conn
          |> put_flash(:info, "Logged in as \#{user[:email]}")
          |> redirect(to: ~p"/")
          |> halt()
        end

        @impl true
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

        @behaviour Amur.Callback

        @impl true
        def on_success(conn, %{user: _user}) do
          redirect(conn, "/")
        end

        @impl true
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

    # Returns `{igniter, router_status}` where `router_status` is one of:
    #
    #   * `:mounted` - Amur.Router is mounted (already, or by this run)
    #   * `:not_mounted` - mounting was attempted and failed, so the user must do it
    #   * `:skipped` - the user passed `--no-router` and no existing mount was found
    defp maybe_add_router(igniter, opts, phoenix?, router) do
      if opts[:router] == false do
        if existing_router_mounted?(igniter, phoenix?, router) do
          {igniter, :mounted}
        else
          {igniter, :skipped}
        end
      else
        add_router(igniter, phoenix?, router)
      end
    end

    defp add_router(igniter, true, router) do
      case phoenix_router_mounted?(igniter, router) do
        true ->
          {Igniter.add_notice(
             igniter,
             "[skip] #{inspect(router)} already forwards to Amur.Router; leaving unchanged."
           ), :mounted}

        :not_found ->
          # `select_router/1` can name a router that `find_module/2` cannot locate,
          # for example one defined through an alias. `Phoenix.has_pipeline/3`
          # would raise on that module, so warn instead of crashing the installer.
          {Igniter.add_warning(
             igniter,
             "Could not find the Phoenix router #{inspect(router)} to mount Amur.Router."
           ), :not_mounted}

        false ->
          {igniter, has_browser_pipeline?} =
            Phoenix.has_pipeline(igniter, router, :browser)

          contents =
            if has_browser_pipeline? do
              """
              pipe_through :browser
              forward "/", Amur.Router
              """
            else
              "forward \"/\", Amur.Router"
            end

          igniter =
            Phoenix.add_scope(
              igniter,
              "/auth",
              contents,
              router: router,
              arg2: [alias: false]
            )

          status =
            if phoenix_router_mounted?(igniter, router) == true, do: :mounted, else: :not_mounted

          {igniter, status}
      end
    end

    defp add_router(igniter, false, _router) do
      {igniter, modules} = plug_router_modules(igniter)

      case modules do
        [module | _] ->
          case ProjectModule.find_and_update_module(igniter, module, &update_plug_router/1) do
            {:ok, igniter} ->
              {igniter, :mounted}

            {:error, igniter} ->
              {Igniter.add_warning(
                 igniter,
                 "Could not find the Plug router #{inspect(module)} to mount Amur.Router."
               ), :not_mounted}
          end

        [] ->
          {Igniter.add_warning(igniter, "Could not find a Plug.Router module to patch."),
           :not_mounted}
      end
    end

    defp plug_router_modules(igniter) do
      ProjectModule.find_all_matching_modules(igniter, fn _module, zipper ->
        match?({:ok, _}, CodeModule.move_to_use(zipper, Plug.Router))
      end)
    end

    defp existing_router_mounted?(igniter, true, router) do
      phoenix_router_mounted?(igniter, router) == true
    end

    defp existing_router_mounted?(igniter, false, _router) do
      {_igniter, modules} = plug_router_modules(igniter)

      Enum.any?(modules, fn module ->
        with {:ok, {_igniter, _source, zipper}} <- ProjectModule.find_module(igniter, module),
             {:ok, zipper} <- Common.move_to_do_block(zipper) do
          has_auth_forward?(zipper)
        else
          _ -> false
        end
      end)
    end

    # Detects an existing Amur mount so re-running the installer in a project that
    # already has one does not add a second `forward` to the same router.
    #
    # The combined scope and forward path must be `/auth`, and the target must
    # resolve to Amur.Router after scope aliasing.
    #
    # Returns `true` when the `/auth` scope already forwards to Amur.Router, `false`
    # when it does not, or `:not_found` when the router module cannot be located, so
    # the caller can warn instead of crashing downstream.
    defp phoenix_router_mounted?(igniter, router) do
      case Igniter.Project.Module.find_module(igniter, router) do
        {:ok, {_igniter, _source, zipper}} ->
          case Common.move_to_do_block(zipper) do
            {:ok, zipper} -> router_body_mounted?(zipper, :phoenix)
            :error -> false
          end

        {:error, _igniter} ->
          :not_found
      end
    end

    # Keep the search inside the selected module and out of quoted helpers and
    # function definitions. Resolve each target with its own lexical environment,
    # so aliases in other modules or declared later cannot change the result.
    defp router_body_mounted?(zipper, kind) do
      {_zipper, mounted?} =
        Zipper.traverse_while(zipper, false, fn call, mounted? ->
          check_router_call(call, mounted?, kind)
        end)

      mounted?
    end

    defp check_router_call(call, mounted?, kind) do
      case Zipper.node(call) do
        {name, _, _} when name in [:defmodule, :def, :defp, :defmacro, :defmacrop, :quote] ->
          {:skip, call, mounted?}

        {:forward, _, [_path, _target | _]} ->
          if amur_forward_call?(call, kind),
            do: {:halt, call, true},
            else: {:cont, call, mounted?}

        _ ->
          {:cont, call, mounted?}
      end
    end

    defp amur_forward_call?(call, kind) do
      with {:ok, path} <- Function.move_to_nth_argument(call, 0),
           path when is_binary(path) <- literal_string(Zipper.node(path)),
           {:ok, target} <- Function.move_to_nth_argument(call, 1) do
        target =
          case CodeKeyword.get_key(target, :to) do
            {:ok, target} -> target
            :error -> target
          end

        case {mounted_scope(call, path, kind), router_module(target)} do
          {{"/auth", aliases}, module} when not is_nil(module) ->
            Module.concat(forward_aliases(call, kind, aliases) ++ [module]) == Amur.Router

          _ ->
            false
        end
      else
        _ -> false
      end
    end

    defp forward_aliases(call, :phoenix, aliases) do
      with {:ok, opts} <- Function.move_to_nth_argument(call, 3),
           {:ok, value} <- CodeKeyword.get_key(opts, :alias),
           true <- Common.nodes_equal?(value, false) do
        []
      else
        _ -> aliases
      end
    end

    defp forward_aliases(_call, _kind, aliases), do: aliases

    defp router_module(zipper) do
      with {:__aliases__, _, _} = alias_ast <- Zipper.node(zipper),
           {:ok, env} <- Common.current_env(zipper),
           module when is_atom(module) <- Macro.expand(alias_ast, env) do
        module
      else
        _ -> nil
      end
    end

    defp mounted_scope(_call, path, :plug), do: {path, []}

    defp mounted_scope(call, path, :phoenix) do
      with scopes when is_list(scopes) <- enclosing_scopes(call, []),
           {paths, aliases} <- scope_prefixes(scopes) do
        full_path =
          "/" <>
            Enum.join(Enum.flat_map(paths ++ [path], &String.split(&1, "/", trim: true)), "/")

        {full_path, aliases}
      else
        _ -> nil
      end
    end

    defp enclosing_scopes(call, scopes) do
      case Zipper.up(call) do
        nil ->
          scopes

        parent ->
          add_enclosing_scope(parent, Zipper.node(parent), scopes)
      end
    end

    defp add_enclosing_scope(parent, {:scope, _, args}, scopes) do
      case scope_settings(Enum.drop(args, -1)) do
        {nil, _namespace} ->
          nil

        {path, namespace} ->
          enclosing_scopes(parent, [{path, scope_namespace(parent, namespace)} | scopes])
      end
    end

    defp add_enclosing_scope(parent, _node, scopes), do: enclosing_scopes(parent, scopes)

    defp scope_prefixes(scopes) do
      Enum.reduce_while(scopes, {[], []}, fn
        {_path, :unknown}, _acc ->
          {:halt, nil}

        {path, namespace}, {paths, aliases} ->
          aliases =
            case namespace do
              nil -> aliases
              false -> []
              module -> aliases ++ [module]
            end

          {:cont, {paths ++ [path], aliases}}
      end)
    end

    defp scope_settings([options]) when is_list(options) do
      path =
        case ast_keyword_value(options, :path) do
          nil -> "/"
          path -> literal_string(path)
        end

      {path, ast_keyword_value(options, :alias)}
    end

    defp scope_settings([path]), do: {literal_string(path), nil}

    defp scope_settings([path, options]) when is_list(options) do
      {literal_string(path), ast_keyword_value(options, :alias)}
    end

    defp scope_settings([path, namespace | _]) do
      {literal_string(path), namespace}
    end

    defp scope_settings(_other), do: {nil, nil}

    defp scope_namespace(_scope, nil), do: nil
    defp scope_namespace(_scope, {:__block__, _, [nil]}), do: nil
    defp scope_namespace(_scope, {:__block__, _, [false]}), do: false

    defp scope_namespace(scope, namespace) do
      router_module(Zipper.replace(scope, namespace)) || :unknown
    end

    defp ast_keyword_value(options, key) do
      Enum.find_value(options, fn
        {{:__block__, _, [^key]}, value} -> value
        _ -> nil
      end)
    end

    # Sourceror wraps string literals in a `{:__block__, meta, [value]}` node, so a
    # plain `"/auth"` pattern would not match the parsed router source.
    defp literal_string({:__block__, _meta, [value]}) when is_binary(value), do: value
    defp literal_string(_other), do: nil

    defp update_plug_router(zipper) do
      if has_auth_forward?(zipper) do
        {:ok, zipper}
      else
        {:ok, patch_plug_router_zipper(zipper)}
      end
    end

    defp has_auth_forward?(zipper) do
      router_body_mounted?(zipper, :plug)
    end

    # Sourceror wraps the `:dispatch` atom in a `{:__block__, meta, [:dispatch]}`
    # node, so a bare `[:dispatch | _]` pattern never matches parsed source.
    defp dispatch_plug?({:plug, _, [{:__block__, _, [:dispatch]}]}), do: true
    defp dispatch_plug?(_other), do: false

    defp patch_plug_router_zipper(zipper) do
      dispatch_call =
        Function.move_to_function_call(zipper, :plug, [1, 2], fn call ->
          dispatch_plug?(Zipper.node(call))
        end)

      forward_ast = Sourceror.parse_string!("forward(\"/auth\", to: Amur.Router)")

      case dispatch_call do
        {:ok, call_zipper} ->
          Zipper.insert_left(call_zipper, forward_ast)

        _ ->
          {:ok, use_zipper} = CodeModule.move_to_use(zipper, Plug.Router)
          Zipper.insert_right(use_zipper, forward_ast)
      end
    end

    # Page-only mode (`--page --no-router --no-controller`) records just the
    # application name, so it must not rewrite the general configuration: doing so
    # would add `base_url`, the dotenv loader and (when `--provider` was omitted)
    # the default GitHub provider to an already configured project.
    defp page_only?(opts) do
      opts[:page] == true && opts[:router] == false && opts[:controller] == false
    end

    defp maybe_add_config(igniter, opts, web_module, providers, phoenix?) do
      cond do
        opts[:config] == false -> igniter
        page_only?(opts) -> igniter
        true -> add_config(igniter, web_module, providers, phoenix?, opts[:controller] != false)
      end
    end

    # The sign-in page is served by `Amur.Router` from Amur's own `priv/`, so
    # `--page` only needs to record the application name the page displays.
    defp maybe_add_page(igniter, opts, app_name) do
      if opts[:page] == true && opts[:config] != false do
        ProjectConfig.configure(
          igniter,
          "runtime.exs",
          :amur,
          [:app_name],
          {:code, Sourceror.parse_string!(inspect(to_string(app_name)))}
        )
      else
        igniter
      end
    end

    defp add_config(igniter, web_module, providers, _phoenix?, controller?) do
      base_url_expr = "System.get_env(\"BASE_URL\") || \"http://localhost:4000\""

      igniter
      |> configure_runtime_default(
        [:base_url],
        {:code, Sourceror.parse_string!(base_url_expr)}
      )
      |> add_provider_config(providers)
      |> maybe_configure_callbacks(web_module, controller?)
      |> add_dotenv_loader()
    end

    defp configure_runtime_default(igniter, path, value) do
      # Keep existing values wherever they were declared. New environment reads
      # must run after a loader already present in the runtime config.
      if ProjectConfig.configures_key?(igniter, "runtime.exs", :amur, path) do
        igniter
      else
        ProjectConfig.configure_new(igniter, "runtime.exs", :amur, path, value,
          after: &top_level_dotenv_loader?/1
        )
      end
    end

    defp top_level_dotenv_loader?(zipper) do
      parent = Zipper.up(zipper)

      top_level? =
        is_nil(parent) or
          (match?({:__block__, _, _}, Zipper.node(parent)) and is_nil(Zipper.up(parent)))

      node = Zipper.node(zipper)
      top_level? and match?({:if, _, _}, node) and dotenv_loader_present?(node)
    end

    defp add_dotenv_loader(igniter) do
      Igniter.update_elixir_file(igniter, "config/runtime.exs", fn zipper ->
        source = zipper |> Zipper.topmost() |> Zipper.node()

        if dotenv_loader_present?(source) do
          {:ok, Zipper.replace(Zipper.topmost(zipper), upgrade_dotenv_loader(source))}
        else
          add_dotenv_loader_code(zipper)
        end
      end)
    end

    # Re-running the installer also repairs the guard emitted by older versions,
    # while preserving the user's loader body and other runtime configuration.
    defp upgrade_dotenv_loader(source) do
      Macro.prewalk(source, fn
        {:if, meta, [condition, body]} = node ->
          if dotenv_loader_present?(node),
            do: {:if, meta, [runtime_env_condition(condition), body]},
            else: node

        node ->
          node
      end)
    end

    defp runtime_env_condition(condition) do
      Macro.prewalk(condition, fn
        {{:., _, [{:__aliases__, _, [:Mix]}, :env]}, meta, []} -> {:config_env, meta, []}
        node -> node
      end)
    end

    defp add_dotenv_loader_code(zipper) do
      case Function.move_to_function_call_in_current_scope(
             zipper,
             :import,
             1,
             &config_import?/1
           ) do
        {:ok, import_zipper} ->
          {:ok, Common.add_code(import_zipper, dotenv_loader())}

        :error ->
          {:ok,
           Common.add_code(zipper, "import Config\n\n" <> dotenv_loader(), placement: :before)}
      end
    end

    defp config_import?(call) do
      Function.argument_matches_predicate?(call, 0, &Common.nodes_equal?(&1, Config))
    end

    defp dotenv_loader_present?(source) do
      rendered_source = Sourceror.to_string(source)

      String.contains?(rendered_source, "File.exists?(\".env\")") and
        String.contains?(rendered_source, "System.put_env(key, val)")
    end

    defp dotenv_loader do
      """
      if config_env() != :test and File.exists?(".env") do
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
      |> configure_runtime_default(
        [:on_success],
        {:code, Sourceror.parse_string!("&#{inspect(web_module)}.AuthController.on_success/2")}
      )
      |> configure_runtime_default(
        [:on_failure],
        {:code, Sourceror.parse_string!("&#{inspect(web_module)}.AuthController.on_failure/2")}
      )
    end

    defp add_provider_config(igniter, providers) do
      Enum.reduce(providers, igniter, fn provider, igniter ->
        credentials =
          provider_env_config(provider)
          |> Enum.map_join(",\n", fn {key, env} ->
            "#{key}: System.fetch_env!(#{inspect(env)})"
          end)

        configure_runtime_default(
          igniter,
          [:providers, provider],
          {:code, Sourceror.parse_string!("[#{credentials}]")}
        )
      end)
    end

    defp provider_env_config(:twitter) do
      [consumer_key: "TWITTER_CLIENT_ID", consumer_secret: "TWITTER_CLIENT_SECRET"]
    end

    defp provider_env_config(provider) do
      keys =
        case provider do
          :apple -> [:client_id, :team_id, :private_key_id, :private_key_path]
          :auth0 -> [:client_id, :client_secret, :base_url]
          :telegram -> [:bot_token, :origin, :return_to]
          :zitadel -> [:client_id, :base_url, :resource_id]
          _ -> [:client_id, :client_secret]
        end

      Enum.map(keys, &{&1, String.upcase("#{provider}_#{&1}")})
    end

    defp queue_next_steps(igniter, web_module, providers, opts, router_status) do
      provider_example = List.first(providers, :github)

      next_steps =
        cond do
          opts[:config] == false ->
            "    No runtime configuration was generated."

          page_only?(opts) ->
            flow_next_step(provider_example, opts, router_status)

          true ->
            env_keys =
              providers
              |> Enum.flat_map(&provider_env_config/1)
              |> Keyword.values()
              |> Enum.join(", ")

            controller_step =
              if opts[:controller] == false do
                "      2. Verify the existing #{inspect(web_module)}.AuthController callbacks."
              else
                "      2. Customize auth success/failure handling:\n         #{inspect(web_module)}.AuthController"
              end

            flow_step = "      3. " <> flow_next_step(provider_example, opts, router_status)

            """
                Required next steps:
                  1. Export the following environment variables:
                     #{env_keys}

            #{controller_step}

            #{flow_step}
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

      igniter
      |> Igniter.add_notice(notice)
      |> maybe_add_telegram_notice(providers, opts)
    end

    defp flow_next_step(_provider, _opts, :not_mounted) do
      "Mount Amur.Router in your router before starting a flow."
    end

    defp flow_next_step(provider, opts, :skipped) do
      if opts[:page] do
        "Mount Amur.Router in your router, then open the sign-in page at:\n         /auth"
      else
        "Mount Amur.Router in your router, then start a flow at:\n         /auth/#{provider}"
      end
    end

    defp flow_next_step(provider, opts, :mounted) do
      if opts[:page] do
        "Open the sign-in page at:\n         /auth"
      else
        "Initiate an OAuth flow at:\n         /auth/#{provider}"
      end
    end

    defp maybe_add_telegram_notice(igniter, providers, opts) do
      if :telegram in providers && opts[:config] != false && not page_only?(opts) do
        Igniter.add_notice(
          igniter,
          "Telegram requires an application-owned return page at TELEGRAM_RETURN_TO that " <>
            "decodes tgAuthResult and forwards it to /auth/telegram/callback, preserving amur_state. " <>
            "See https://hexdocs.pm/amur/Amur.Providers.Telegram.html"
        )
      else
        igniter
      end
    end
  end
else
  defmodule Mix.Tasks.Amur.Install do
    @shortdoc "Generates Amur auth boilerplate (requires Igniter)"
    @moduledoc false
    use Mix.Task

    @impl Mix.Task
    def run(_args) do
      Mix.raise(
        "mix amur.install requires Igniter. Add {:igniter, \"~> 0.8\"} to your dependencies and try again."
      )
    end
  end
end

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
  #   * `:skipped` - the user passed `--no-router`, so the installer did not look
  #
  # The three states are kept distinct so the next steps only tell the user to
  # mount Amur.Router when mounting actually failed, rather than also when they
  # explicitly opted out.
  defp maybe_add_router(igniter, opts, phoenix?, router) do
    if opts[:router] == false do
      {igniter, :skipped}
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

        {Phoenix.add_scope(
           igniter,
           "/auth",
           contents,
           router: router,
           arg2: [alias: false]
         ), :mounted}
    end
  end

  defp add_router(igniter, false, _router) do
    igniter = Igniter.include_all_elixir_files(igniter)

    {igniter, modules} =
      ProjectModule.find_all_matching_modules(igniter, fn _module, zipper ->
        match?({:ok, _}, CodeModule.move_to_use(zipper, Plug.Router))
      end)

    case modules do
      [module | _] ->
        {ProjectModule.find_and_update_module!(
           igniter,
           module,
           &update_plug_router/1
         ), :mounted}

      [] ->
        {Igniter.add_warning(igniter, "Could not find a Plug.Router module to patch."),
         :not_mounted}
    end
  end

  # Detects an existing Amur mount so re-running the installer in a project that
  # already has one does not add a second `forward` to the same router.
  #
  # Only a `forward "/", Amur.Router` inside the `/auth` scope counts: a project
  # that forwards Amur somewhere else (for example `/oauth`) still needs the
  # documented `/auth` mount, so a whole-file match would wrongly skip it.
  defp phoenix_router_mounted?(igniter, router) do
    case Igniter.Project.Module.find_module(igniter, router) do
      {:ok, {_igniter, _source, zipper}} ->
        zipper
        |> Zipper.topmost()
        |> Zipper.node()
        |> auth_scope_amur_forward?()

      {:error, _igniter} ->
        :not_found
    end
  end

  defp auth_scope_amur_forward?(ast) do
    aliases = collect_aliases(ast)

    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {:scope, _, [path | _]} = node, acc ->
          {node,
           acc || (literal_string(path) == "/auth" && scope_contains_amur_forward?(node, aliases))}

        node, acc ->
          {node, acc}
      end)

    found?
  end

  defp scope_contains_amur_forward?(scope_ast, aliases) do
    scope_ast
    |> scope_body()
    |> Enum.any?(&root_amur_forward?(&1, aliases))
  end

  # The statements directly inside a `scope` block, without descending into
  # nested scopes. A `forward` in a nested scope is mounted at a deeper path
  # (for example `/auth/nested`), so it must not satisfy the top-level `/auth`
  # mount check. `Macro.prewalk/3` cannot express this: returning a node
  # unchanged still descends into it, so nested scopes have to be stopped by
  # not walking them at all.
  defp scope_body({:scope, _, [_path, _opts, [{{:__block__, _, [:do]}, body}]]}),
    do: scope_statements(body)

  defp scope_body({:scope, _, [_path, [{{:__block__, _, [:do]}, body}]]}),
    do: scope_statements(body)

  defp scope_body(_other), do: []

  defp scope_statements({:__block__, _, statements}), do: statements
  defp scope_statements(statement), do: [statement]

  defp root_amur_forward?({:forward, _, [path, router]}, aliases),
    do: literal_string(path) == "/" && resolve_forward_target(router, aliases) == Amur.Router

  defp root_amur_forward?(_other, _aliases), do: false

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
    aliases = zipper |> Zipper.topmost() |> Zipper.node() |> collect_aliases()

    match?(
      {:ok, _},
      Function.move_to_function_call(zipper, :forward, 2, fn call ->
        auth_forward_call?(Zipper.node(call), aliases)
      end)
    )
  end

  defp auth_forward_call?({:forward, _, [path, opts]}, aliases) do
    literal_string(path) == "/auth" and
      opts |> forward_target() |> resolve_forward_target(aliases) == Amur.Router
  end

  # Sourceror wraps the `:dispatch` atom in a `{:__block__, meta, [:dispatch]}`
  # node, so a bare `[:dispatch | _]` pattern never matches parsed source.
  defp dispatch_plug?({:plug, _, [{:__block__, _, [:dispatch]}]}), do: true
  defp dispatch_plug?(_other), do: false

  # Extracts the router from a `forward` call's second argument, which may be a
  # bare module (`forward "/auth", Amur.Router`) or a `to:` keyword list
  # (`forward "/auth", to: Amur.Router`). Sourceror nests the keyword list and
  # wraps its key, so both shapes are normalized here.
  defp forward_target(opts) when is_list(opts) do
    opts
    |> List.flatten()
    |> Enum.find_value(fn
      {{:__block__, _, [:to]}, value} -> value
      _ -> nil
    end)
  end

  defp forward_target(other), do: other

  # Resolves a `forward` target written as an alias (for example `Router` after
  # `alias Amur.Router`) to the module it names, so an existing mount is
  # recognized no matter how the project chose to spell it. `alias: false` on
  # the surrounding scope only disables Phoenix's controller aliasing; a
  # module-level `alias` still applies, so the AST alone is not enough.
  defp resolve_forward_target({:__aliases__, _, segments}, aliases) when is_list(segments) do
    expand_alias_segments(segments, aliases)
  end

  defp resolve_forward_target(_other, _aliases), do: nil

  # Expands the first segment of an alias against the module's `alias`
  # declarations, mirroring how the compiler resolves `Router` to
  # `Amur.Router`. A leading `Elixir.` segment is already fully qualified.
  defp expand_alias_segments([:"Elixir" | rest], _aliases), do: Module.concat(rest)

  defp expand_alias_segments([head | rest], aliases) do
    case Map.fetch(aliases, head) do
      {:ok, module} -> Module.concat([module | rest])
      :error -> Module.concat([head | rest])
    end
  end

  # Collects the module-level `alias` declarations from a router's AST into a
  # map of the local name to the module it points at. Only the simple
  # `alias Foo.Bar` and `alias Foo.Bar, as: Baz` forms are tracked, which is
  # what a router uses to shorten `Amur.Router`.
  defp collect_aliases(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, %{}, fn
        {:alias, _, [target | opts]} = node, acc ->
          {node, put_alias(acc, target, opts)}

        node, acc ->
          {node, acc}
      end)

    aliases
  end

  defp put_alias(acc, target, opts) do
    case alias_target(target) do
      {:ok, module} ->
        name =
          case alias_as(opts) do
            {:__aliases__, _, [as]} -> as
            _ -> module |> Module.split() |> List.last() |> String.to_atom()
          end

        Map.put(acc, name, module)

      :error ->
        acc
    end
  end

  # Sourceror wraps keyword keys in `{:__block__, meta, [:as]}` and nests the
  # keyword list one level deeper than `Keyword.get/2` expects, so neither a
  # plain lookup nor a flat scan finds the `as:` option on a parsed alias.
  defp alias_as(opts) do
    opts
    |> List.flatten()
    |> Enum.find_value(fn
      {{:__block__, _, [:as]}, value} -> value
      _ -> nil
    end)
  end

  defp alias_target({:__aliases__, _, segments}) when is_list(segments) do
    {:ok, Module.concat(segments)}
  end

  defp alias_target(_other), do: :error

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

    providers_code = providers_config_code(providers)

    igniter
    |> ProjectConfig.configure(
      "runtime.exs",
      :amur,
      [:base_url],
      {:code, Sourceror.parse_string!(base_url_expr)}
    )
    |> ProjectConfig.configure(
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
      source = zipper |> Zipper.topmost() |> Zipper.node()

      if dotenv_loader_present?(source) do
        {:ok, zipper}
      else
        add_dotenv_loader_code(zipper)
      end
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
        {:ok, Common.add_code(zipper, dotenv_loader(), placement: :before)}
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
    |> ProjectConfig.configure(
      "runtime.exs",
      :amur,
      [:on_success],
      {:code, Sourceror.parse_string!("&#{inspect(web_module)}.AuthController.on_success/2")}
    )
    |> ProjectConfig.configure(
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

  defp queue_next_steps(igniter, web_module, providers, opts, router_status) do
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

        flow_step =
          cond do
            router_status == :not_mounted ->
              "      3. Mount Amur.Router in your router before starting a flow."

            opts[:page] ->
              "      3. Open the sign-in page at:\n         /auth"

            true ->
              "      3. Initiate an OAuth flow at:\n         /auth/#{provider_example}"
          end

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

    Igniter.add_notice(igniter, notice)
  end
end

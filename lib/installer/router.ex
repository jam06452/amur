if Code.ensure_loaded?(Igniter) do
  defmodule Amur.Installer.Router do
    @moduledoc false

    alias Igniter.Code.{Common, Function}
    alias Igniter.Code.Keyword, as: CodeKeyword
    alias Sourceror.Zipper

    # Keep the search inside the selected module and out of quoted helpers and
    # function definitions. Resolve each target with its own lexical environment,
    # so aliases in other modules or declared later cannot change the result.
    def mounted?(zipper, kind) do
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
  end
end

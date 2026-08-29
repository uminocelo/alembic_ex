defmodule Alembic.Evaluator do
  @moduledoc """
  Tree-walking interpreter: walks an `Alembic.AST.t()` against a
  `Alembic.Context`, resolves variables and expressions, applies filters,
  and emits the rendered output as a string.

  Output is accumulated as an iolist (nested lists of binaries), flattened
  once at the end via `IO.iodata_to_binary/1` — O(n) rather than the O(n²)
  cost of repeated `<>` concatenation.

  `{:assign, var, expr}` must be able to affect every node evaluated *after*
  it at the same template level, so `eval_nodes/2` threads `Context` through
  an `Enum.reduce_while/3` fold rather than a plain `Enum.map/2`.

  Whitespace control (`strip_left`/`strip_right`) is already resolved by
  `Alembic.Parser` before the AST reaches this module — see that module's
  moduledoc. There is nothing left for the Evaluator to strip.

  `{:extends, _}` / `{:block, _, _}` nodes are never seen here: they are
  resolved away by `Alembic.Inheritance.preprocess/2` one level up, in the
  top-level render pipeline, before `eval/2` is called.

  `{:include, name, variables}` loads and evaluates a partial via
  `ctx.loader_fn` (see `Alembic.Context.loader/2`) — the included template
  runs in a child scope seeded with `variables`, so it can still see the
  including template's own scopes/assigns (classic `{% include %}`
  semantics, not an isolated `{% render %}`). It is not run through
  `Alembic.Inheritance.preprocess/2` — a partial is not expected to use
  `extends`/`block` itself.
  """

  alias Alembic.{AST, Context, Filters, Lexer, Parser}

  @type reason ::
          {:undefined_variable, [String.t()]}
          | {:include_not_found, String.t(), term()}
          | :include_loader_not_configured
          | {:include_compile_error, term()}
          | Filters.reason()

  @doc """
  Renders an AST against a `Alembic.Context`, producing the final output
  string.

  ## Examples

      iex> ast = [{:text, "Hello, "}, {:output, ["name"], []}, {:text, "!"}]
      iex> Alembic.Evaluator.eval(ast, Alembic.Context.new(%{"name" => "World"}))
      {:ok, "Hello, World!"}

      iex> ast = [{:output, ["missing"], []}]
      iex> ctx = Alembic.Context.new(%{}) |> Alembic.Context.strict(true)
      iex> Alembic.Evaluator.eval(ast, ctx)
      {:error, {:undefined_variable, ["missing"]}}
  """
  @spec eval([AST.ast_node()], Context.t()) :: {:ok, String.t()} | {:error, reason()}
  def eval(nodes, %Context{} = ctx) when is_list(nodes) do
    case eval_nodes(nodes, ctx) do
      {:ok, iolist, _ctx} -> {:ok, IO.iodata_to_binary(iolist)}
      {:error, reason} -> {:error, reason}
    end
  end

  # Returns {:ok, iodata, new_ctx} | {:error, reason} — every eval_node/2
  # clause returns this same shape so assign's context change threads
  # through the fold below to every sibling node that follows it.
  defp eval_nodes(nodes, ctx) do
    Enum.reduce_while(nodes, {:ok, [], ctx}, fn node, {:ok, acc, ctx} ->
      case eval_node(node, ctx) do
        {:ok, chunk, new_ctx} -> {:cont, {:ok, [acc, chunk], new_ctx}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp eval_node({:text, content}, ctx), do: {:ok, content, ctx}

  defp eval_node({:output, path, filters}, ctx) do
    with {:ok, value} <- resolve_or_error(ctx, path),
         {:ok, filter_pairs} <- eval_filter_list(filters, ctx),
         {:ok, filtered} <- Filters.apply_chain(value, filter_pairs, ctx) do
      {:ok, to_output_string(filtered), ctx}
    end
  end

  defp eval_node({:if, condition, then_branch, elsifs, else_branch}, ctx) do
    with {:ok, cond_value} <- eval_expr(condition, ctx) do
      if truthy?(cond_value) do
        eval_nodes(then_branch, ctx)
      else
        eval_elsifs(elsifs, else_branch, ctx)
      end
    end
  end

  defp eval_node({:for, var, iterable_expr, body, else_branch}, ctx) do
    with {:ok, iterable} <- eval_expr(iterable_expr, ctx) do
      case coerce_to_list(iterable) do
        [] -> eval_optional_branch(else_branch, ctx)
        items -> eval_for_items(items, var, body, ctx)
      end
    end
  end

  defp eval_node({:assign, var, expr}, ctx) do
    with {:ok, value} <- eval_expr(expr, ctx) do
      {:ok, "", Context.assign(ctx, var, value)}
    end
  end

  defp eval_node({:include, name, variables}, ctx) do
    with {:ok, loader_fn} <- require_loader(ctx),
         {:ok, source} <- call_loader(loader_fn, name),
         {:ok, ast} <- compile_include(source),
         {:ok, resolved_vars} <- eval_var_map(variables, ctx) do
      include_ctx = Context.push_scope(ctx, resolved_vars)

      case eval_nodes(ast, include_ctx) do
        {:ok, chunk, new_include_ctx} -> {:ok, chunk, Context.pop_scope(new_include_ctx)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp eval_elsifs([{cond_expr, branch} | rest], else_branch, ctx) do
    with {:ok, cond_value} <- eval_expr(cond_expr, ctx) do
      if truthy?(cond_value) do
        eval_nodes(branch, ctx)
      else
        eval_elsifs(rest, else_branch, ctx)
      end
    end
  end

  defp eval_elsifs([], else_branch, ctx), do: eval_optional_branch(else_branch, ctx)

  defp eval_optional_branch(nil, ctx), do: {:ok, "", ctx}
  defp eval_optional_branch(branch, ctx), do: eval_nodes(branch, ctx)

  defp eval_for_items(items, var, body, ctx) do
    length = Enum.count(items)

    items
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], ctx}, fn {item, index}, {:ok, acc, loop_ctx} ->
      scope = Map.put(Context.forloop_meta(index, length, item), var, item)
      iter_ctx = Context.push_scope(loop_ctx, scope)

      case eval_nodes(body, iter_ctx) do
        {:ok, chunk, new_iter_ctx} -> {:cont, {:ok, [acc, chunk], Context.pop_scope(new_iter_ctx)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp coerce_to_list(value) when is_list(value), do: value
  defp coerce_to_list(_other), do: []

  defp require_loader(%Context{loader_fn: nil}), do: {:error, :include_loader_not_configured}
  defp require_loader(%Context{loader_fn: loader_fn}), do: {:ok, loader_fn}

  defp call_loader(loader_fn, name) do
    case loader_fn.(name) do
      {:ok, source} -> {:ok, source}
      {:error, reason} -> {:error, {:include_not_found, name, reason}}
    end
  end

  defp compile_include(source) do
    with {:ok, tokens} <- Lexer.tokenize(source),
         {:ok, ast} <- Parser.parse(tokens) do
      {:ok, ast}
    else
      {:error, reason} -> {:error, {:include_compile_error, reason}}
    end
  end

  defp eval_var_map(variables, ctx) do
    Enum.reduce_while(variables, {:ok, %{}}, fn {key, expr}, {:ok, acc} ->
      case eval_expr(expr, ctx) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # Lenient by default: an undefined path resolves to nil (output renders
  # ""; conditions treat it as falsy). Strict mode — set on the Context via
  # `Alembic.Context.strict/2`, driven by `Alembic.render/3`'s `strict:
  # true` option — turns that into a hard error instead, at the exact point
  # a path fails to resolve, whether inside an output tag or an expression.
  defp resolve_or_error(ctx, path) do
    case Context.resolve_path(ctx, path) do
      {:ok, value} -> {:ok, value}
      :not_found when ctx.strict -> {:error, {:undefined_variable, path}}
      :not_found -> {:ok, nil}
    end
  end

  # ---- Expression evaluation ----

  defp eval_expr({:variable, path}, ctx), do: resolve_or_error(ctx, path)

  defp eval_expr({:literal, value}, _ctx), do: {:ok, value}

  defp eval_expr({:filter_chain, base_expr, filters}, ctx) do
    with {:ok, base_value} <- eval_expr(base_expr, ctx),
         {:ok, filter_pairs} <- eval_filter_list(filters, ctx) do
      Filters.apply_chain(base_value, filter_pairs, ctx)
    end
  end

  defp eval_expr({:compare, op, left_expr, right_expr}, ctx) do
    with {:ok, left} <- eval_expr(left_expr, ctx),
         {:ok, right} <- eval_expr(right_expr, ctx) do
      {:ok, compare(op, left, right)}
    end
  end

  defp eval_expr({:logical, :and, left_expr, right_expr}, ctx) do
    with {:ok, left} <- eval_expr(left_expr, ctx) do
      if truthy?(left), do: eval_expr(right_expr, ctx), else: {:ok, left}
    end
  end

  defp eval_expr({:logical, :or, left_expr, right_expr}, ctx) do
    with {:ok, left} <- eval_expr(left_expr, ctx) do
      if truthy?(left), do: {:ok, left}, else: eval_expr(right_expr, ctx)
    end
  end

  defp eval_expr({:not, expr}, ctx) do
    with {:ok, value} <- eval_expr(expr, ctx) do
      {:ok, not truthy?(value)}
    end
  end

  defp eval_filter_list(filters, ctx) do
    Enum.reduce_while(filters, {:ok, []}, fn {:filter, name, arg_exprs}, {:ok, acc} ->
      case eval_args(arg_exprs, ctx) do
        {:ok, args} -> {:cont, {:ok, [{name, args} | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, pairs} -> {:ok, Enum.reverse(pairs)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp eval_args(arg_exprs, ctx) do
    Enum.reduce_while(arg_exprs, {:ok, []}, fn expr, {:ok, acc} ->
      case eval_expr(expr, ctx) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      {:error, reason} -> {:error, reason}
    end
  end

  # Liquid truthiness: only nil and false are falsy — 0, "", and [] are all
  # truthy. This is intentionally different from Elixir's own truthiness.
  defp truthy?(nil), do: false
  defp truthy?(false), do: false
  defp truthy?(_other), do: true

  defp compare(:eq, left, right), do: left == right
  defp compare(:neq, left, right), do: left != right
  defp compare(:gt, left, right), do: left > right
  defp compare(:lt, left, right), do: left < right
  defp compare(:gte, left, right), do: left >= right
  defp compare(:lte, left, right), do: left <= right
  defp compare(:contains, left, right), do: contains?(left, right)

  defp contains?(left, right) when is_binary(left) and is_binary(right) do
    String.contains?(left, right)
  end

  defp contains?(left, right) when is_list(left), do: right in left
  defp contains?(_left, _right), do: false

  defp to_output_string(nil), do: ""
  defp to_output_string(value) when is_binary(value), do: value
  defp to_output_string(value) when is_integer(value), do: Integer.to_string(value)
  defp to_output_string(value) when is_float(value), do: Float.to_string(value)
  defp to_output_string(true), do: "true"
  defp to_output_string(false), do: "false"
  defp to_output_string(value) when is_list(value), do: Enum.map_join(value, "", &to_output_string/1)
  defp to_output_string(value), do: to_string(value)
end

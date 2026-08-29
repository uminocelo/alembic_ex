defmodule Alembic.Inheritance do
  @moduledoc """
  Template inheritance: `{% extends "base.html" %}` / `{% block name %}` /
  `{% endblock %}` and multi-level chains. Pure — no direct file I/O; a
  loader function is injected so this module is testable without a
  filesystem.

  Two-pass structure, directly analogous to a multi-pass compiler:

    * **Pass 1 — collect** (`collect_blocks/1`): walk a template's AST and
      gather its `{:block, name, body}` definitions into a `name => body`
      map — a symbol-collection pass.
    * **Pass 2 — resolve** (`resolve/2`): walk a (possibly different)
      template's AST and splice each `{:block, name, default}` node's body
      for the matching override from the collected map, or keep `default`
      when there is none — a symbol-resolution / linking pass. The child's
      block bodies are the object-file symbols; the parent template is the
      shared library with unresolved references; `resolve/2` is the linker.

  `resolve/2` always **splices** the winning body directly into the
  surrounding node list — `{:block, _, _}` nodes never survive into the
  final AST. `Alembic.Evaluator` has no clause for `:block` at all; by the
  time `preprocess/2` hands it an AST, every block has already become
  ordinary content.

  ## Multi-level resolution order (why blocks can't resolve level-by-level)

  Naively resolving each parent/child pair as soon as it's loaded doesn't
  work for 3+ levels: resolving grandparent-vs-parent first would splice
  away the grandparent's `{:block, "title", _}` placeholder *before* the
  child ever gets a chance to override it. Instead, `resolve_chain/3` walks
  all the way up to the root ancestor (the first template with no
  `{:extends, _}`), **merging** each level's own blocks into an
  accumulator as it goes (closer-to-child levels win on a name collision),
  and only calls `resolve/2` once, at the root, against the root's
  never-touched original AST.

  ## Deviations from a literal reading of issue 1.4.4

  - `collect_blocks/1` returns `{:ok, map} | {:error, {:duplicate_block,
    name}}`, not a bare map — the issue's own task list requires erroring on
    a duplicate block name, which a bare-map return type cannot express.
  - `block.super` substitution is shallow: only `{:output, ["block",
    "super"], []}` nodes directly in an override's own body are replaced —
    it does not recurse into nested `if`/`for` branches inside that
    override. This matches the issue's own worked example, which only shows
    top-level usage.
  """

  alias Alembic.{AST, Lexer, Parser}

  @type loader_fn :: (String.t() -> {:ok, String.t()} | {:error, term()})
  @type reason ::
          {:duplicate_block, String.t()}
          | {:circular_inheritance, String.t()}
          | :inheritance_depth_exceeded
          | {:parent_compile_error, term()}
          | term()

  @max_depth 10

  @spec collect_blocks([AST.ast_node()]) ::
          {:ok, %{String.t() => [AST.ast_node()]}} | {:error, {:duplicate_block, String.t()}}
  def collect_blocks(nodes), do: do_collect_blocks(nodes, %{})

  @spec resolve([AST.ast_node()], %{String.t() => [AST.ast_node()]}) :: [AST.ast_node()]
  def resolve(nodes, child_blocks), do: Enum.flat_map(nodes, &resolve_node(&1, child_blocks))

  @spec resolve_chain([AST.ast_node()], loader_fn(), MapSet.t()) ::
          {:ok, [AST.ast_node()]} | {:error, reason()}
  def resolve_chain(ast, loader_fn, visited \\ MapSet.new()) do
    do_resolve_chain(ast, loader_fn, visited, %{})
  end

  @spec preprocess([AST.ast_node()], loader_fn()) :: {:ok, [AST.ast_node()]} | {:error, reason()}
  def preprocess(ast, loader_fn) do
    case find_extends(ast) do
      nil -> {:ok, ast}
      _parent_name -> resolve_chain(ast, loader_fn)
    end
  end

  # ---- Pass 1: collect ----

  defp do_collect_blocks([], acc), do: {:ok, acc}

  defp do_collect_blocks([{:block, name, body} | rest], acc) do
    if Map.has_key?(acc, name) do
      {:error, {:duplicate_block, name}}
    else
      do_collect_blocks(rest, Map.put(acc, name, body))
    end
  end

  defp do_collect_blocks([{:if, _cond, then_b, elsifs, else_b} | rest], acc) do
    with {:ok, acc2} <- do_collect_blocks(then_b, acc),
         {:ok, acc3} <- collect_from_elsifs(elsifs, acc2),
         {:ok, acc4} <- do_collect_blocks(else_b || [], acc3) do
      do_collect_blocks(rest, acc4)
    end
  end

  defp do_collect_blocks([{:for, _var, _iterable, body, else_b} | rest], acc) do
    with {:ok, acc2} <- do_collect_blocks(body, acc),
         {:ok, acc3} <- do_collect_blocks(else_b || [], acc2) do
      do_collect_blocks(rest, acc3)
    end
  end

  defp do_collect_blocks([_other | rest], acc), do: do_collect_blocks(rest, acc)

  defp collect_from_elsifs([], acc), do: {:ok, acc}

  defp collect_from_elsifs([{_cond, branch} | rest], acc) do
    with {:ok, acc2} <- do_collect_blocks(branch, acc) do
      collect_from_elsifs(rest, acc2)
    end
  end

  # ---- Pass 2: resolve ----

  defp resolve_node({:block, name, default_body}, child_blocks) do
    case Map.fetch(child_blocks, name) do
      {:ok, override_body} -> substitute_block_super(override_body, default_body)
      :error -> default_body
    end
  end

  defp resolve_node({:if, condition, then_b, elsifs, else_b}, child_blocks) do
    [
      {:if, condition, resolve(then_b, child_blocks), resolve_elsifs(elsifs, child_blocks),
       resolve_maybe(else_b, child_blocks)}
    ]
  end

  defp resolve_node({:for, var, iterable, body, else_b}, child_blocks) do
    [{:for, var, iterable, resolve(body, child_blocks), resolve_maybe(else_b, child_blocks)}]
  end

  defp resolve_node(other, _child_blocks), do: [other]

  defp resolve_maybe(nil, _child_blocks), do: nil
  defp resolve_maybe(body, child_blocks), do: resolve(body, child_blocks)

  defp resolve_elsifs(elsifs, child_blocks) do
    Enum.map(elsifs, fn {condition, branch} -> {condition, resolve(branch, child_blocks)} end)
  end

  defp substitute_block_super(override_body, default_body) do
    Enum.flat_map(override_body, fn
      {:output, ["block", "super"], []} -> default_body
      other -> [other]
    end)
  end

  # ---- Chain walking ----

  defp do_resolve_chain(ast, loader_fn, visited, accumulated_blocks) do
    with {:ok, own_blocks} <- collect_blocks(ast) do
      merged_blocks = Map.merge(own_blocks, accumulated_blocks)

      case find_extends(ast) do
        nil -> {:ok, resolve(ast, merged_blocks)}
        parent_name -> load_parent(parent_name, loader_fn, visited, merged_blocks)
      end
    end
  end

  defp load_parent(parent_name, loader_fn, visited, merged_blocks) do
    cond do
      MapSet.size(visited) >= @max_depth ->
        {:error, :inheritance_depth_exceeded}

      MapSet.member?(visited, parent_name) ->
        {:error, {:circular_inheritance, parent_name}}

      true ->
        with {:ok, parent_source} <- loader_fn.(parent_name),
             {:ok, parent_ast} <- compile_source(parent_source) do
          do_resolve_chain(parent_ast, loader_fn, MapSet.put(visited, parent_name), merged_blocks)
        end
    end
  end

  defp find_extends([{:extends, name} | _rest]), do: name
  defp find_extends(_ast), do: nil

  defp compile_source(source) do
    with {:ok, tokens} <- Lexer.tokenize(source),
         {:ok, ast} <- Parser.parse(tokens) do
      {:ok, ast}
    else
      {:error, reason} -> {:error, {:parent_compile_error, reason}}
    end
  end
end

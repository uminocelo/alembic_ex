defmodule Alembic.Context do
  @moduledoc """
  Runtime variable store the Evaluator uses to resolve variable paths.

  Behaves as a scoped symbol table: a stack of maps (`scopes`), head is the
  innermost scope. Inner scopes shadow outer scopes without mutating them —
  `push_scope/2` and `pop_scope/1` are pure and always return a new struct.
  `{% assign %}` variables live in `assigns`, consulted after every scope.
  """

  @enforce_keys [:scopes]
  defstruct scopes: [], assigns: %{}, strict: false, loader_fn: nil

  @type loader_fn :: (String.t() -> {:ok, String.t()} | {:error, term()})
  @type t :: %__MODULE__{
          scopes: [map()],
          assigns: map(),
          strict: boolean(),
          loader_fn: loader_fn() | nil
        }

  @doc """
  Wraps an initial bindings map as the root scope.

  ## Examples

      iex> ctx = Alembic.Context.new(%{"name" => "Alice"})
      iex> Alembic.Context.lookup(ctx, "name")
      {:ok, "Alice"}
  """
  @spec new(map()) :: t()
  def new(bindings) when is_map(bindings) do
    %__MODULE__{scopes: [bindings], assigns: %{}}
  end

  @doc """
  Enables or disables strict mode: when `true`, an undefined variable path
  makes `Alembic.Evaluator` return `{:error, {:undefined_variable, path}}`
  instead of rendering as an empty string / evaluating as `nil`. Used by
  `Alembic.render/3`'s `strict: true` option (issue 1.5.3).

  ## Examples

      iex> ctx = Alembic.Context.new(%{}) |> Alembic.Context.strict(true)
      iex> ctx.strict
      true
  """
  @spec strict(t(), boolean()) :: t()
  def strict(%__MODULE__{} = ctx, value) when is_boolean(value), do: %{ctx | strict: value}

  @doc """
  Sets the loader function `Alembic.Evaluator` uses to resolve
  `{% include %}` targets. Not part of issue 1.4.1's original spec — added
  when integration testing (issue 1.5.4) revealed `{:include, _, _}` had no
  `eval_node` clause at all in the Evaluator (issue 1.4.2's task list never
  listed it, unlike `extends`/`block` which were explicitly deferred to
  `Alembic.Inheritance`). Threading a loader function through a new
  positional parameter on every `eval_nodes`/`eval_node` call would have
  touched far more of the Evaluator than storing it once here.

  ## Examples

      iex> ctx = Alembic.Context.new(%{}) |> Alembic.Context.loader(fn _name -> {:error, :not_found} end)
      iex> is_function(ctx.loader_fn, 1)
      true
  """
  @spec loader(t(), loader_fn()) :: t()
  def loader(%__MODULE__{} = ctx, loader_fn) when is_function(loader_fn, 1),
    do: %{ctx | loader_fn: loader_fn}

  @doc """
  Pushes a new innermost scope (entering a `{% for %}` body or an
  `{% include %}`). Pure — returns a new struct, never mutates.

  ## Examples

      iex> ctx = Alembic.Context.new(%{"name" => "Alice"})
      iex> ctx = Alembic.Context.push_scope(ctx, %{"name" => "Bob"})
      iex> Alembic.Context.lookup(ctx, "name")
      {:ok, "Bob"}
  """
  @spec push_scope(t(), map()) :: t()
  def push_scope(%__MODULE__{scopes: scopes} = ctx, bindings) when is_map(bindings) do
    %{ctx | scopes: [bindings | scopes]}
  end

  @doc """
  Pops the innermost scope, restoring whatever was shadowed. Raises if
  called on the root scope — popping past the root is a programming error.

  ## Examples

      iex> ctx = Alembic.Context.new(%{"name" => "Alice"})
      iex> ctx = ctx |> Alembic.Context.push_scope(%{"name" => "Bob"}) |> Alembic.Context.pop_scope()
      iex> Alembic.Context.lookup(ctx, "name")
      {:ok, "Alice"}
  """
  @spec pop_scope(t()) :: t()
  def pop_scope(%__MODULE__{scopes: [_root]}) do
    raise ArgumentError, "cannot pop the root scope"
  end

  def pop_scope(%__MODULE__{scopes: [_innermost | rest]} = ctx) do
    %{ctx | scopes: rest}
  end

  @doc """
  Looks up a single variable name, searching scopes from innermost to
  outermost, then `assigns` last.

  ## Examples

      iex> ctx = Alembic.Context.new(%{"name" => "Alice"})
      iex> Alembic.Context.lookup(ctx, "name")
      {:ok, "Alice"}

      iex> ctx = Alembic.Context.new(%{})
      iex> Alembic.Context.lookup(ctx, "missing")
      :not_found
  """
  @spec lookup(t(), String.t()) :: {:ok, any()} | :not_found
  def lookup(%__MODULE__{scopes: scopes, assigns: assigns}, key) do
    case find_in_scopes(scopes, key) do
      {:ok, value} -> {:ok, value}
      :not_found -> find_in_map(assigns, key)
    end
  end

  @doc """
  Resolves a dot-notation path, traversing nested maps, keyword lists, and
  list indices after the first segment.

  ## Examples

      iex> ctx = Alembic.Context.new(%{"user" => %{"address" => %{"city" => "Lisbon"}}})
      iex> Alembic.Context.resolve_path(ctx, ["user", "address", "city"])
      {:ok, "Lisbon"}

      iex> ctx = Alembic.Context.new(%{"posts" => ["a", "b", "c"]})
      iex> Alembic.Context.resolve_path(ctx, ["posts", "1"])
      {:ok, "b"}
  """
  @spec resolve_path(t(), [String.t()]) :: {:ok, any()} | :not_found
  def resolve_path(%__MODULE__{} = ctx, [head | rest]) do
    case lookup(ctx, head) do
      {:ok, value} -> traverse(value, rest)
      :not_found -> :not_found
    end
  end

  @doc """
  Sets a `{% assign %}` variable. Always lands in the root-level `assigns`
  map, so it persists across `push_scope/2`/`pop_scope/1` cycles (e.g. it
  survives a `{% for %}` loop ending).

  ## Examples

      iex> ctx = Alembic.Context.new(%{}) |> Alembic.Context.assign("count", 10)
      iex> Alembic.Context.lookup(ctx, "count")
      {:ok, 10}
  """
  @spec assign(t(), String.t(), any()) :: t()
  def assign(%__MODULE__{assigns: assigns} = ctx, key, value) do
    %{ctx | assigns: Map.put(assigns, key, value)}
  end

  @doc """
  Builds the `"forloop"` metadata map injected into a `{% for %}` body's
  scope for one iteration.

  ## Examples

      iex> Alembic.Context.forloop_meta(0, 3, "a")
      %{"forloop" => %{"index" => 1, "index0" => 0, "rindex" => 3, "rindex0" => 2, "first" => true, "last" => false, "length" => 3}}
  """
  @spec forloop_meta(non_neg_integer(), non_neg_integer(), any()) :: map()
  def forloop_meta(index, length, _value) do
    %{
      "forloop" => %{
        "index" => index + 1,
        "index0" => index,
        "rindex" => length - index,
        "rindex0" => length - index - 1,
        "first" => index == 0,
        "last" => index == length - 1,
        "length" => length
      }
    }
  end

  defp find_in_scopes([], _key), do: :not_found

  defp find_in_scopes([scope | rest], key) do
    case find_in_map(scope, key) do
      {:ok, value} -> {:ok, value}
      :not_found -> find_in_scopes(rest, key)
    end
  end

  defp traverse(value, []), do: {:ok, value}

  defp traverse(value, [segment | rest]) do
    case fetch_segment(value, segment) do
      {:ok, next} -> traverse(next, rest)
      :not_found -> :not_found
    end
  end

  defp fetch_segment(map, key) when is_map(map), do: find_in_map(map, key)

  defp fetch_segment(list, key) when is_list(list) do
    if Keyword.keyword?(list) do
      fetch_keyword(list, key)
    else
      fetch_list_index(list, key)
    end
  end

  defp fetch_segment(_other, _key), do: :not_found

  defp fetch_keyword(list, key) do
    with {:ok, atom_key} <- safe_to_existing_atom(key),
         {:ok, value} <- Keyword.fetch(list, atom_key) do
      {:ok, value}
    else
      _ -> :not_found
    end
  end

  defp fetch_list_index(list, key) do
    with {index, ""} <- Integer.parse(key),
         true <- index >= 0 and index < length(list) do
      {:ok, Enum.at(list, index)}
    else
      _ -> :not_found
    end
  end

  defp find_in_map(map, key) do
    if Map.has_key?(map, key) do
      {:ok, Map.get(map, key)}
    else
      find_in_map_by_atom(map, key)
    end
  end

  defp find_in_map_by_atom(map, key) do
    with {:ok, atom_key} <- safe_to_existing_atom(key),
         true <- Map.has_key?(map, atom_key) do
      {:ok, Map.get(map, atom_key)}
    else
      _ -> :not_found
    end
  end

  defp safe_to_existing_atom(key) do
    {:ok, String.to_existing_atom(key)}
  rescue
    ArgumentError -> :error
  end
end

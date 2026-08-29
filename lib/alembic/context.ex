defmodule Alembic.Context do
  @moduledoc """
  Runtime variable store the Evaluator uses to resolve variable paths.

  Behaves as a scoped symbol table: a stack of maps (`scopes`), head is the
  innermost scope. Inner scopes shadow outer scopes without mutating them —
  `push_scope/2` and `pop_scope/1` are pure and always return a new struct.
  `{% assign %}` variables live in `assigns`, consulted after every scope.
  """

  @enforce_keys [:scopes]
  defstruct scopes: [], assigns: %{}

  @type t :: %__MODULE__{scopes: [map()], assigns: map()}

  @spec new(map()) :: t()
  def new(bindings) when is_map(bindings) do
    %__MODULE__{scopes: [bindings], assigns: %{}}
  end

  @spec push_scope(t(), map()) :: t()
  def push_scope(%__MODULE__{scopes: scopes} = ctx, bindings) when is_map(bindings) do
    %{ctx | scopes: [bindings | scopes]}
  end

  @spec pop_scope(t()) :: t()
  def pop_scope(%__MODULE__{scopes: [_root]}) do
    raise ArgumentError, "cannot pop the root scope"
  end

  def pop_scope(%__MODULE__{scopes: [_innermost | rest]} = ctx) do
    %{ctx | scopes: rest}
  end

  @spec lookup(t(), String.t()) :: {:ok, any()} | :not_found
  def lookup(%__MODULE__{scopes: scopes, assigns: assigns}, key) do
    case find_in_scopes(scopes, key) do
      {:ok, value} -> {:ok, value}
      :not_found -> find_in_map(assigns, key)
    end
  end

  @spec resolve_path(t(), [String.t()]) :: {:ok, any()} | :not_found
  def resolve_path(%__MODULE__{} = ctx, [head | rest]) do
    case lookup(ctx, head) do
      {:ok, value} -> traverse(value, rest)
      :not_found -> :not_found
    end
  end

  @spec assign(t(), String.t(), any()) :: t()
  def assign(%__MODULE__{assigns: assigns} = ctx, key, value) do
    %{ctx | assigns: Map.put(assigns, key, value)}
  end

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

defmodule Alembic.Parser do
  @moduledoc """
  Recursive descent parser: turns the flat token list produced by
  `Alembic.Lexer` into a typed `Alembic.AST.t()`.

  Each `parse_*` function is a direct implementation of a production rule in
  `docs/grammar.md`. Expression content (inside `{{ }}` and after tag
  keywords) is delegated to `Alembic.Parser.Expression`.

  `Alembic.Token.t()` carries a `line`/`col` position (see
  `Alembic.Token.position/1`). `:unexpected_token` is the one error below
  that names a concrete leftover token, so it's the one that surfaces this
  position; the other error reasons here (`:malformed_for`,
  `:invalid_expression`, etc.) operate on already-extracted tag/expression
  content rather than a token, so they don't carry one.

  ## Whitespace control is resolved here, not in the Evaluator

  `Alembic.AST` node types have no field for `strip_left`/`strip_right` —
  adding one would mean threading strip intent through every node shape and
  back out again at render time. Instead, `parse/1` resolves whitespace
  control immediately, as a pass over the raw token list before any node is
  built: an output/tag token's `strip_left`/`strip_right` flag trims the
  adjacent `:text` token in place. By the time `parse_template/1` builds the
  AST, the whitespace is already gone — the tree the Evaluator walks needs no
  strip metadata at all.
  """

  alias Alembic.{AST, Parser.Expression, Token}

  @type reason ::
          {:unexpected_token, Token.t(), Token.position()}
          | {:missing_end_tag, String.t()}
          | :extends_not_first
          | {:unsupported_output_expression, String.t()}
          | {:invalid_expression, String.t(), Expression.reason()}
          | {:malformed_for, String.t()}
          | {:malformed_assign, term()}
          | {:malformed_extends, term()}
          | {:malformed_include, term()}
          | {:unexpected_tag, String.t()}

  @doc """
  Turns a token list (from `Alembic.Lexer.tokenize/1`) into an
  `Alembic.AST.t()`.

  ## Examples

      iex> {:ok, tokens} = Alembic.Lexer.tokenize("{% if x %}hi{% endif %}")
      iex> Alembic.Parser.parse(tokens)
      {:ok, [{:if, {:variable, ["x"]}, [{:text, "hi"}], [], nil}]}

      iex> {:ok, tokens} = Alembic.Lexer.tokenize("{% if x %}no close")
      iex> Alembic.Parser.parse(tokens)
      {:error, {:missing_end_tag, "endif"}}
  """
  @spec parse([Token.t()]) :: {:ok, AST.t()} | {:error, reason()}
  def parse(tokens) when is_list(tokens) do
    case tokens |> apply_whitespace_control() |> parse_template() do
      {:ok, nodes, []} -> validate_extends_position(nodes)
      {:ok, _nodes, [token | _rest]} -> {:error, {:unexpected_token, token, Token.position(token)}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Like `parse/1`, but tries to keep going after an error instead of
  stopping at the first one, so a single call can report every independent
  problem in a template rather than making the caller fix-and-reparse one
  error at a time. `{:ok, ast}` only when there are zero errors;
  `{:error, [reason(), ...]}` otherwise, one entry per error found, in the
  order encountered.

  Recovery is best-effort, not a guarantee of precise error isolation: on
  an error, it skips forward until the next `{% tag %}` or `{{ output }}`
  token (or end of input) and resumes from there. A single malformed
  construct — e.g. an `{% if %}` with a genuinely broken tag nested inside
  it — can therefore surface as more than one reported error: the real one,
  plus a spurious one from resuming mid-construct. Treat the result as "at
  least these problems exist," not as N precisely-located, independent
  errors. `parse/1` remains the right choice whenever only the first error
  matters (that's still every existing caller of this module).

  ## Examples

      iex> {:ok, tokens} = Alembic.Lexer.tokenize("{% if x %}hi{% endif %}")
      iex> Alembic.Parser.parse_all(tokens)
      {:ok, [{:if, {:variable, ["x"]}, [{:text, "hi"}], [], nil}]}

      iex> {:ok, tokens} = Alembic.Lexer.tokenize("{% if x %}a{% endfor %}{{ y ** }}")
      iex> Alembic.Parser.parse_all(tokens)
      {:error,
       [
         {:missing_end_tag, "endif"},
         {:invalid_expression, "y **", {:unknown_operator, "**"}}
       ]}
  """
  @spec parse_all([Token.t()]) :: {:ok, AST.t()} | {:error, [reason(), ...]}
  def parse_all(tokens) when is_list(tokens) do
    {nodes, node_errors} = tokens |> apply_whitespace_control() |> collect_errors([], [])

    case node_errors ++ extends_position_errors(nodes) do
      [] -> {:ok, nodes}
      errors -> {:error, errors}
    end
  end

  defp extends_position_errors(nodes) do
    case validate_extends_position(nodes) do
      {:ok, _nodes} -> []
      {:error, reason} -> [reason]
    end
  end

  # ---- parse_all/1's error-collecting, best-effort-recovering walk ----

  defp collect_errors([], node_acc, error_acc) do
    {Enum.reverse(node_acc), Enum.reverse(error_acc)}
  end

  defp collect_errors([token | rest] = tokens, node_acc, error_acc) do
    if stopping_token?(token) do
      error = {:unexpected_token, token, Token.position(token)}
      collect_errors(rest, node_acc, [error | error_acc])
    else
      case parse_node(tokens) do
        {:ok, node, remaining} -> collect_errors(remaining, [node | node_acc], error_acc)
        {:error, reason} -> collect_errors(resync(tokens), node_acc, [reason | error_acc])
      end
    end
  end

  defp resync([_failed_token | rest]), do: drop_until_resumable(rest)

  # A `{% tag %}` or `{{ output }}` token could start a fresh, independent
  # construct — except a "stopping" tag (`else`/`endif`/`endfor`/
  # `endblock`/`elsif ...`), which is debris from the construct that just
  # failed, not a new one; skip past those too instead of reporting them
  # as their own `:unexpected_token` error.
  defp drop_until_resumable([]), do: []

  defp drop_until_resumable([token | rest]) do
    if resumable?(token), do: [token | rest], else: drop_until_resumable(rest)
  end

  defp resumable?({:output, _content, _sl, _sr, _pos}), do: true
  defp resumable?({:tag, _content, _sl, _sr, _pos} = token), do: not stopping_token?(token)
  defp resumable?(_other), do: false

  # ---- Whitespace control: strip flags trim adjacent :text tokens in place ----

  defp apply_whitespace_control(tokens) do
    tuple = List.to_tuple(tokens)

    tuple
    |> strip_right_pass()
    |> strip_left_pass()
    |> Tuple.to_list()
  end

  defp strip_right_pass(tuple) when tuple_size(tuple) < 2, do: tuple

  defp strip_right_pass(tuple) do
    Enum.reduce(0..(tuple_size(tuple) - 2)//1, tuple, fn i, acc ->
      if strip_right?(elem(acc, i)), do: trim_text_at(acc, i + 1, :leading), else: acc
    end)
  end

  defp strip_left_pass(tuple) when tuple_size(tuple) < 2, do: tuple

  defp strip_left_pass(tuple) do
    Enum.reduce(1..(tuple_size(tuple) - 1)//1, tuple, fn i, acc ->
      if strip_left?(elem(acc, i)), do: trim_text_at(acc, i - 1, :trailing), else: acc
    end)
  end

  defp strip_right?({:output, _content, _sl, true, _pos}), do: true
  defp strip_right?({:tag, _content, _sl, true, _pos}), do: true
  defp strip_right?(_token), do: false

  defp strip_left?({:output, _content, true, _sr, _pos}), do: true
  defp strip_left?({:tag, _content, true, _sr, _pos}), do: true
  defp strip_left?(_token), do: false

  defp trim_text_at(tuple, index, :leading) do
    case elem(tuple, index) do
      {:text, content, pos} -> put_elem(tuple, index, {:text, String.trim_leading(content), pos})
      _other -> tuple
    end
  end

  defp trim_text_at(tuple, index, :trailing) do
    case elem(tuple, index) do
      {:text, content, pos} -> put_elem(tuple, index, {:text, String.trim_trailing(content), pos})
      _other -> tuple
    end
  end

  # ---- Template: a sequence of nodes, stopping at else/elsif/end* tags ----

  defp parse_template(tokens), do: parse_template(tokens, [])

  defp parse_template([], acc), do: {:ok, Enum.reverse(acc), []}

  defp parse_template([token | _rest] = tokens, acc) do
    if stopping_token?(token) do
      {:ok, Enum.reverse(acc), tokens}
    else
      with {:ok, node, rest} <- parse_node(tokens) do
        parse_template(rest, [node | acc])
      end
    end
  end

  defp stopping_token?({:tag, "else", _strip_left, _strip_right, _pos}), do: true
  defp stopping_token?({:tag, "endif", _strip_left, _strip_right, _pos}), do: true
  defp stopping_token?({:tag, "endfor", _strip_left, _strip_right, _pos}), do: true
  defp stopping_token?({:tag, "endblock", _strip_left, _strip_right, _pos}), do: true
  defp stopping_token?({:tag, "elsif " <> _rest, _strip_left, _strip_right, _pos}), do: true
  defp stopping_token?(_token), do: false

  # ---- Single node dispatch ----

  defp parse_node([{:text, content, _pos} | rest]), do: {:ok, {:text, content}, rest}

  defp parse_node([{:output, raw, _strip_left, _strip_right, _pos} | rest]) do
    case Expression.parse(raw) do
      {:ok, expr} -> output_node_from_expr(expr, raw, rest)
      {:error, reason} -> {:error, {:invalid_expression, raw, reason}}
    end
  end

  defp parse_node([{:tag, content, _strip_left, _strip_right, _pos} | rest]) do
    dispatch_tag(content, rest)
  end

  defp output_node_from_expr({:variable, path}, _raw, rest), do: {:ok, {:output, path, []}, rest}

  defp output_node_from_expr({:filter_chain, {:variable, path}, filters}, _raw, rest) do
    {:ok, {:output, path, filters}, rest}
  end

  defp output_node_from_expr(_other, raw, _rest) do
    {:error, {:unsupported_output_expression, raw}}
  end

  # ---- Tag keyword dispatch (tag content is already trimmed by the Lexer) ----

  defp dispatch_tag("if " <> condition_raw, rest), do: parse_if(condition_raw, rest)
  defp dispatch_tag("for " <> spec, rest), do: parse_for(spec, rest)
  defp dispatch_tag("assign " <> spec, rest), do: parse_assign(spec, rest)
  defp dispatch_tag("extends " <> raw, rest), do: parse_extends(raw, rest)
  defp dispatch_tag("block " <> name, rest), do: parse_block(String.trim(name), rest)
  defp dispatch_tag("include " <> raw, rest), do: parse_include(raw, rest)
  defp dispatch_tag(other, _rest), do: {:error, {:unexpected_tag, other}}

  # ---- If / elsif* / else? / endif ----

  defp parse_if(condition_raw, tokens) do
    with {:ok, condition} <- Expression.parse(condition_raw),
         {:ok, then_branch, rest} <- parse_template(tokens),
         {:ok, elsif_branches, rest2} <- parse_elsifs(rest),
         {:ok, else_branch, rest3} <- parse_optional_else(rest2),
         {:ok, rest4} <- expect_tag(rest3, "endif") do
      {:ok, {:if, condition, then_branch, elsif_branches, else_branch}, rest4}
    end
  end

  defp parse_elsifs(tokens), do: parse_elsifs(tokens, [])

  defp parse_elsifs([{:tag, "elsif " <> condition_raw, _sl, _sr, _pos} | rest], acc) do
    with {:ok, condition} <- Expression.parse(condition_raw),
         {:ok, branch, rest2} <- parse_template(rest) do
      parse_elsifs(rest2, [{condition, branch} | acc])
    end
  end

  defp parse_elsifs(tokens, acc), do: {:ok, Enum.reverse(acc), tokens}

  defp parse_optional_else([{:tag, "else", _sl, _sr, _pos} | rest]), do: parse_template(rest)
  defp parse_optional_else(tokens), do: {:ok, nil, tokens}

  # ---- For var in iterable / else? / endfor ----

  defp parse_for(spec, tokens) do
    with {:ok, var_name, iterable_raw} <- split_for_spec(spec),
         {:ok, iterable} <- Expression.parse(iterable_raw),
         {:ok, body, rest} <- parse_template(tokens),
         {:ok, else_branch, rest2} <- parse_optional_else(rest),
         {:ok, rest3} <- expect_tag(rest2, "endfor") do
      {:ok, {:for, var_name, iterable, body, else_branch}, rest3}
    end
  end

  defp split_for_spec(spec) do
    case String.split(spec, " in ", parts: 2) do
      [var_name, iterable_raw] -> {:ok, String.trim(var_name), iterable_raw}
      _other -> {:error, {:malformed_for, spec}}
    end
  end

  # ---- Assign ----

  defp parse_assign(spec, tokens) do
    case String.split(spec, "=", parts: 2) do
      [var_name, value_raw] ->
        case Expression.parse(value_raw) do
          {:ok, value} -> {:ok, {:assign, String.trim(var_name), value}, tokens}
          {:error, reason} -> {:error, {:malformed_assign, reason}}
        end

      _other ->
        {:error, {:malformed_assign, spec}}
    end
  end

  # ---- Template inheritance: extends / block ----

  defp parse_extends(raw, tokens) do
    case Expression.parse(String.trim(raw)) do
      {:ok, {:literal, name}} when is_binary(name) -> {:ok, {:extends, name}, tokens}
      {:ok, _other} -> {:error, {:malformed_extends, raw}}
      {:error, reason} -> {:error, {:malformed_extends, reason}}
    end
  end

  defp parse_block(name, tokens) do
    with {:ok, body, rest} <- parse_template(tokens),
         {:ok, rest2} <- expect_tag(rest, "endblock") do
      {:ok, {:block, name, body}, rest2}
    end
  end

  # ---- Include ----

  defp parse_include(raw, tokens) do
    case String.split(raw, " with ", parts: 2) do
      [name_raw] ->
        with {:ok, name} <- parse_include_name(name_raw) do
          {:ok, {:include, name, %{}}, tokens}
        end

      [name_raw, vars_raw] ->
        with {:ok, name} <- parse_include_name(name_raw),
             {:ok, variables} <- parse_include_variables(vars_raw) do
          {:ok, {:include, name, variables}, tokens}
        end
    end
  end

  defp parse_include_name(raw) do
    case Expression.parse(String.trim(raw)) do
      {:ok, {:literal, name}} when is_binary(name) -> {:ok, name}
      {:ok, _other} -> {:error, {:malformed_include, raw}}
      {:error, reason} -> {:error, {:malformed_include, reason}}
    end
  end

  defp parse_include_variables(raw) do
    raw
    |> split_top_level_commas()
    |> Enum.reduce_while({:ok, %{}}, fn pair_raw, {:ok, acc} ->
      case parse_assignment_pair(pair_raw) do
        {:ok, key, expr} -> {:cont, {:ok, Map.put(acc, key, expr)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp parse_assignment_pair(pair_raw) do
    case String.split(pair_raw, ":", parts: 2) do
      [key_raw, value_raw] ->
        case Expression.parse(value_raw) do
          {:ok, expr} -> {:ok, String.trim(key_raw), expr}
          {:error, reason} -> {:error, {:malformed_include, reason}}
        end

      _other ->
        {:error, {:malformed_include, pair_raw}}
    end
  end

  defp split_top_level_commas(str), do: split_top_level_commas(str, [], [], nil)

  defp split_top_level_commas("", current, acc, nil) do
    Enum.reverse([iodata_to_string(current) | acc])
  end

  defp split_top_level_commas(<<c::utf8, rest::binary>>, current, acc, nil) when c in [?", ?'] do
    split_top_level_commas(rest, [<<c::utf8>> | current], acc, c)
  end

  defp split_top_level_commas(<<c::utf8, rest::binary>>, current, acc, quote) when c == quote do
    split_top_level_commas(rest, [<<c::utf8>> | current], acc, nil)
  end

  defp split_top_level_commas(<<?,, rest::binary>>, current, acc, nil) do
    split_top_level_commas(rest, [], [iodata_to_string(current) | acc], nil)
  end

  defp split_top_level_commas(<<c::utf8, rest::binary>>, current, acc, quote) do
    split_top_level_commas(rest, [<<c::utf8>> | current], acc, quote)
  end

  defp iodata_to_string(reversed_chars),
    do: reversed_chars |> Enum.reverse() |> IO.iodata_to_binary()

  # ---- Shared helpers ----

  defp expect_tag([{:tag, content, _sl, _sr, _pos} | rest], name) do
    if content == name, do: {:ok, rest}, else: {:error, {:missing_end_tag, name}}
  end

  defp expect_tag(_tokens, name), do: {:error, {:missing_end_tag, name}}

  defp validate_extends_position(nodes) do
    case Enum.find_index(nodes, &match?({:extends, _template_name}, &1)) do
      nil -> {:ok, nodes}
      0 -> {:ok, nodes}
      _index -> {:error, :extends_not_first}
    end
  end
end

defmodule Alembic.Parser.Expression do
  @moduledoc """
  Parses the raw string content of a Liquid expression — everything that can
  appear inside `{{ ... }}` output tags and `{% if ... %}` / `{% for ... in
  ... %}` conditions — into an `Alembic.AST.expr()` node.

  Grammar (see `docs/grammar.md`):

      expr             = or_expr ;
      or_expr          = and_expr , { "or" , and_expr } ;
      and_expr         = not_expr , { "and" , not_expr } ;
      not_expr         = [ "not" ] , comparison ;
      comparison       = filtered_primary , [ compare_op , filtered_primary ] ;
      filtered_primary = primary , { filter } ;
      primary          = variable | literal ;
      filter           = "|" , IDENT , [ ":" , expr , { "," , expr } ] ;

  Filters bind tighter than comparison and logical operators — this lets a
  bare `"name | upcase"` parse on its own (used for output tags) while still
  allowing filtered operands inside a condition, e.g. `x | size > 0`.
  """

  alias Alembic.AST

  @type reason ::
          :empty_expression
          | :unterminated_string
          | :missing_filter_name
          | {:unknown_operator, String.t()}
          | {:unexpected_token, term()}
          | :range_not_allowed

  @doc """
  Parses the raw string content of an output tag or a tag condition into an
  `Alembic.AST.expr()`.

  ## Examples

      iex> Alembic.Parser.Expression.parse("user.name")
      {:ok, {:variable, ["user", "name"]}}

      iex> Alembic.Parser.Expression.parse("name | upcase")
      {:ok, {:filter_chain, {:variable, ["name"]}, [{:filter, "upcase", []}]}}

      iex> Alembic.Parser.Expression.parse("x > 0 and not skip")
      {:ok,
       {:logical, :and, {:compare, :gt, {:variable, ["x"]}, {:literal, 0}},
        {:not, {:variable, ["skip"]}}}}
  """
  @spec parse(String.t()) :: {:ok, AST.expr()} | {:error, reason()}
  def parse(source) when is_binary(source), do: parse(source, false)

  @doc """
  Like `parse/1`, but `allow_ranges: true` permits `(from..to)` range
  literals. Ranges are restricted to the `{% for %}` iterable position;
  calling `parse/1` (or `parse/2` without the flag) on a range returns
  `{:error, :range_not_allowed}`.
  """
  @spec parse(String.t(), boolean()) :: {:ok, AST.expr()} | {:error, reason()}
  def parse(source, allow_ranges) when is_binary(source) and is_boolean(allow_ranges) do
    case String.trim(source) do
      "" ->
        {:error, :empty_expression}

      trimmed ->
        with {:ok, tokens} <- tokenize(trimmed),
             {:ok, expr, []} <- parse_or(tokens, true, allow_ranges) do
          {:ok, expr}
        else
          {:ok, _expr, [token | _rest]} -> {:error, {:unexpected_token, token}}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # ---- Recursive descent (precedence, low to high): or, and, not, comparison ----
  #
  # `allow_filters` is `false` while parsing a filter's own arguments — see
  # parse_filter_args/1 below for why: without it, `x | f: arg | g` is
  # ambiguous, and this precedence chain would silently parse it as
  # `x | f: (arg | g)` instead of the intended `(x | f: arg) | g`.

  defp parse_or(tokens, allow_filters, allow_ranges) do
    with {:ok, left, rest} <- parse_and(tokens, allow_filters, allow_ranges) do
      parse_or_rest(left, rest, allow_filters, allow_ranges)
    end
  end

  defp parse_or_rest(left, [:or | rest], allow_filters, allow_ranges) do
    with {:ok, right, rest2} <- parse_and(rest, allow_filters, allow_ranges) do
      parse_or_rest({:logical, :or, left, right}, rest2, allow_filters, allow_ranges)
    end
  end

  defp parse_or_rest(left, rest, _allow_filters, _allow_ranges), do: {:ok, left, rest}

  defp parse_and(tokens, allow_filters, allow_ranges) do
    with {:ok, left, rest} <- parse_not(tokens, allow_filters, allow_ranges) do
      parse_and_rest(left, rest, allow_filters, allow_ranges)
    end
  end

  defp parse_and_rest(left, [:and | rest], allow_filters, allow_ranges) do
    with {:ok, right, rest2} <- parse_not(rest, allow_filters, allow_ranges) do
      parse_and_rest({:logical, :and, left, right}, rest2, allow_filters, allow_ranges)
    end
  end

  defp parse_and_rest(left, rest, _allow_filters, _allow_ranges), do: {:ok, left, rest}

  defp parse_not([:not | rest], allow_filters, allow_ranges) do
    with {:ok, expr, rest2} <- parse_comparison(rest, allow_filters, allow_ranges) do
      {:ok, {:not, expr}, rest2}
    end
  end

  defp parse_not(tokens, allow_filters, allow_ranges),
    do: parse_comparison(tokens, allow_filters, allow_ranges)

  @compare_ops [:eq, :neq, :gt, :lt, :gte, :lte, :contains]

  defp parse_comparison(tokens, allow_filters, allow_ranges) do
    with {:ok, left, rest} <- parse_operand(tokens, allow_filters, allow_ranges) do
      parse_comparison_rhs(left, rest, allow_filters, allow_ranges)
    end
  end

  defp parse_comparison_rhs(left, [{:op, op} | rest], allow_filters, allow_ranges)
       when op in @compare_ops do
    with {:ok, right, rest2} <- parse_operand(rest, allow_filters, allow_ranges) do
      {:ok, {:compare, op, left, right}, rest2}
    end
  end

  defp parse_comparison_rhs(left, rest, _allow_filters, _allow_ranges), do: {:ok, left, rest}

  defp parse_operand(tokens, true, allow_ranges), do: parse_filtered_primary(tokens, allow_ranges)
  defp parse_operand(tokens, false, allow_ranges), do: parse_primary(tokens, allow_ranges)

  defp parse_filtered_primary(tokens, allow_ranges) do
    with {:ok, primary, rest} <- parse_primary(tokens, allow_ranges) do
      collect_filters(rest, [], primary)
    end
  end

  defp collect_filters([:pipe | rest], acc, base) do
    case rest do
      [{:ident, name} | rest2] ->
        with {:ok, args, rest3} <- parse_filter_args(rest2) do
          collect_filters(rest3, [{:filter, name, args} | acc], base)
        end

      _ ->
        {:error, :missing_filter_name}
    end
  end

  defp collect_filters(tokens, [], base), do: {:ok, base, tokens}

  defp collect_filters(tokens, acc, base),
    do: {:ok, {:filter_chain, base, Enum.reverse(acc)}, tokens}

  defp parse_filter_args([:colon | rest]) do
    with {:ok, first_arg, rest2} <- parse_or(rest, false, false) do
      collect_more_filter_args(rest2, [first_arg])
    end
  end

  defp parse_filter_args(tokens), do: {:ok, [], tokens}

  defp collect_more_filter_args([:comma | rest], acc) do
    with {:ok, arg, rest2} <- parse_or(rest, false, false) do
      collect_more_filter_args(rest2, [arg | acc])
    end
  end

  defp collect_more_filter_args(tokens, acc), do: {:ok, Enum.reverse(acc), tokens}

  defp parse_primary([{:string, s} | rest], _allow_ranges), do: {:ok, {:literal, s}, rest}
  defp parse_primary([{:int, n} | rest], _allow_ranges), do: {:ok, {:literal, n}, rest}
  defp parse_primary([{:float, f} | rest], _allow_ranges), do: {:ok, {:literal, f}, rest}
  defp parse_primary([{:bool, b} | rest], _allow_ranges), do: {:ok, {:literal, b}, rest}
  defp parse_primary([:nil_lit | rest], _allow_ranges), do: {:ok, {:literal, nil}, rest}

  defp parse_primary([{:ident, name} | rest], allow_ranges),
    do: parse_variable_path([name], rest, allow_ranges)

  defp parse_primary([:lparen | rest], true), do: parse_range(rest)
  defp parse_primary([:lparen | _rest], false), do: {:error, :range_not_allowed}

  defp parse_primary([], _allow_ranges), do: {:error, {:unexpected_token, :eof}}
  defp parse_primary([token | _rest], _allow_ranges), do: {:error, {:unexpected_token, token}}

  defp parse_range(tokens) do
    with {:ok, from, [:dotdot | rest2]} <- parse_or(tokens, true, false),
         {:ok, to, [:rparen | rest3]} <- parse_or(rest2, true, false) do
      {:ok, {:range, from, to}, rest3}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, {:unexpected_token, :expected_rparen}}
    end
  end

  defp parse_variable_path(segments, [:dot | rest], allow_ranges) do
    case rest do
      [{:ident, name} | rest2] ->
        parse_variable_path([name | segments], rest2, allow_ranges)

      [{:int, n} | rest2] ->
        parse_variable_path([Integer.to_string(n) | segments], rest2, allow_ranges)

      _ ->
        {:error, {:unexpected_token, :expected_identifier_after_dot}}
    end
  end

  defp parse_variable_path(segments, [:lbracket, {:string, key}, :rbracket | rest], allow_ranges) do
    parse_variable_path([key | segments], rest, allow_ranges)
  end

  defp parse_variable_path(segments, [:lbracket, {:int, index}, :rbracket | rest], allow_ranges) do
    parse_variable_path([Integer.to_string(index) | segments], rest, allow_ranges)
  end

  defp parse_variable_path(_segments, [:lbracket | _rest], _allow_ranges) do
    {:error, {:unexpected_token, :expected_bracket_key}}
  end

  defp parse_variable_path(segments, rest, _allow_ranges) do
    {:ok, {:variable, Enum.reverse(segments)}, rest}
  end

  # ---- Tokenizer ----

  @symbol_chars ~c"+-*/%^&$#@!~?<>="

  defp tokenize(input), do: tokenize(input, [])

  defp tokenize("", acc), do: {:ok, Enum.reverse(acc)}

  defp tokenize(<<c::utf8, rest::binary>>, acc) when c in [?\s, ?\t, ?\n, ?\r] do
    tokenize(rest, acc)
  end

  defp tokenize("==" <> rest, acc), do: tokenize(rest, [{:op, :eq} | acc])
  defp tokenize("!=" <> rest, acc), do: tokenize(rest, [{:op, :neq} | acc])
  defp tokenize(">=" <> rest, acc), do: tokenize(rest, [{:op, :gte} | acc])
  defp tokenize("<=" <> rest, acc), do: tokenize(rest, [{:op, :lte} | acc])
  defp tokenize(">" <> rest, acc), do: tokenize(rest, [{:op, :gt} | acc])
  defp tokenize("<" <> rest, acc), do: tokenize(rest, [{:op, :lt} | acc])
  defp tokenize(".." <> rest, acc), do: tokenize(rest, [:dotdot | acc])
  defp tokenize("." <> rest, acc), do: tokenize(rest, [:dot | acc])
  defp tokenize("[" <> rest, acc), do: tokenize(rest, [:lbracket | acc])
  defp tokenize("]" <> rest, acc), do: tokenize(rest, [:rbracket | acc])
  defp tokenize("|" <> rest, acc), do: tokenize(rest, [:pipe | acc])
  defp tokenize(":" <> rest, acc), do: tokenize(rest, [:colon | acc])
  defp tokenize("," <> rest, acc), do: tokenize(rest, [:comma | acc])
  defp tokenize("(" <> rest, acc), do: tokenize(rest, [:lparen | acc])
  defp tokenize(")" <> rest, acc), do: tokenize(rest, [:rparen | acc])

  defp tokenize("\"" <> rest, acc) do
    case scan_string(rest, ?", []) do
      {:ok, content, remaining} -> tokenize(remaining, [{:string, content} | acc])
      :error -> {:error, :unterminated_string}
    end
  end

  defp tokenize("'" <> rest, acc) do
    case scan_string(rest, ?', []) do
      {:ok, content, remaining} -> tokenize(remaining, [{:string, content} | acc])
      :error -> {:error, :unterminated_string}
    end
  end

  defp tokenize(<<?-, c::utf8, _::binary>> = input, acc) when c in ?0..?9 do
    scan_number(input, acc)
  end

  defp tokenize(<<c::utf8, _::binary>> = input, acc) when c in ?0..?9 do
    scan_number(input, acc)
  end

  defp tokenize(<<c::utf8, _::binary>> = input, acc)
       when c in ?a..?z or c in ?A..?Z or c == ?_ do
    scan_ident(input, acc)
  end

  defp tokenize(<<c::utf8, _::binary>> = input, _acc) when c in @symbol_chars do
    {symbol, _rest} = take_symbol_run(input, [])
    {:error, {:unknown_operator, symbol}}
  end

  defp tokenize(<<c::utf8, _rest::binary>>, _acc) do
    {:error, {:unexpected_token, <<c::utf8>>}}
  end

  defp scan_string(<<c::utf8, rest::binary>>, close, acc) when c == close do
    {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  end

  defp scan_string("", _close, _acc), do: :error

  defp scan_string(<<c::utf8, rest::binary>>, close, acc) do
    scan_string(rest, close, [<<c::utf8>> | acc])
  end

  defp scan_number(input, acc) do
    {sign, rest} =
      case input do
        "-" <> r -> {"-", r}
        r -> {"", r}
      end

    {int_part, rest2} = take_digits(rest, [])

    case rest2 do
      <<?., c::utf8, _::binary>> when c in ?0..?9 ->
        "." <> after_dot = rest2
        {frac_part, rest3} = take_digits(after_dot, [])
        value = String.to_float(sign <> int_part <> "." <> frac_part)
        tokenize(rest3, [{:float, value} | acc])

      _ ->
        value = String.to_integer(sign <> int_part)
        tokenize(rest2, [{:int, value} | acc])
    end
  end

  defp take_digits(<<c::utf8, rest::binary>>, acc) when c in ?0..?9 do
    take_digits(rest, [<<c::utf8>> | acc])
  end

  defp take_digits(rest, acc), do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}

  @keywords %{
    "true" => {:bool, true},
    "false" => {:bool, false},
    "nil" => :nil_lit,
    "null" => :nil_lit,
    "and" => :and,
    "or" => :or,
    "not" => :not,
    "contains" => {:op, :contains}
  }

  defp scan_ident(input, acc) do
    {word, rest} = take_ident_chars(input, [])
    token = Map.get(@keywords, word, {:ident, word})
    tokenize(rest, [token | acc])
  end

  defp take_ident_chars(<<c::utf8, rest::binary>>, acc)
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ do
    take_ident_chars(rest, [<<c::utf8>> | acc])
  end

  defp take_ident_chars(rest, acc), do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}

  defp take_symbol_run(<<c::utf8, rest::binary>>, acc) when c in @symbol_chars do
    take_symbol_run(rest, [<<c::utf8>> | acc])
  end

  defp take_symbol_run(rest, acc), do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}
end

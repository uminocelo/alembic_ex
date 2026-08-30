defmodule Alembic.Lexer do
  @moduledoc """
  Convert Alembic template source into lexical tokens.
  """

  alias Alembic.Token

  defmodule State do
    @moduledoc false
    defstruct tokens: [], line: 1, col: 1
  end

  @type position :: Token.position()
  @type reason ::
          {:unterminated_output, position()}
          | {:unterminated_tag, position()}
          | {:empty_output_tag, position()}
          | {:unterminated_comment, position()}
          | {:unterminated_raw, position()}

  @doc """
  Converts raw template source into a flat list of `Alembic.Token.t()`.

  ## Examples

      iex> Alembic.Lexer.tokenize("Hello {{ name }}!")
      {:ok,
       [
         {:text, "Hello ", %{line: 1, col: 1}},
         {:output, "name", false, false, %{line: 1, col: 7}},
         {:text, "!", %{line: 1, col: 17}}
       ]}

      iex> Alembic.Lexer.tokenize("{{ name")
      {:error, {:unterminated_output, %{line: 1, col: 1}}}
  """
  @spec tokenize(String.t()) :: {:ok, [Token.t()]} | {:error, reason()}
  def tokenize(source) when is_binary(source) do
    do_tokenize(source, %State{})
  end

  defp do_tokenize("", state), do: finish(state)

  defp do_tokenize("{{-" <> rest, state) do
    start_pos = position(state)
    open_output(true, rest, advance(state, 3), start_pos)
  end

  defp do_tokenize("{{" <> rest, state) do
    start_pos = position(state)
    open_output(false, rest, advance(state, 2), start_pos)
  end

  defp do_tokenize("{%-" <> rest, state) do
    start_pos = position(state)
    open_tag(true, rest, advance(state, 3), start_pos)
  end

  defp do_tokenize("{%" <> rest, state) do
    start_pos = position(state)
    open_tag(false, rest, advance(state, 2), start_pos)
  end

  defp do_tokenize(<<char::utf8, rest::binary>>, state) do
    pos = position(state)

    state =
      state
      |> push({:text, <<char::utf8>>, pos})
      |> advance_char(<<char::utf8>>)

    do_tokenize(rest, state)
  end

  defp open_output(strip_left, rest, state, start_pos) do
    case extract_output_until(rest, state) do
      {:ok, raw_content, strip_right, remaining, state} ->
        content = String.trim(raw_content)

        if content == "" do
          {:error, {:empty_output_tag, start_pos}}
        else
          do_tokenize(
            remaining,
            push(state, {:output, content, strip_left, strip_right, start_pos})
          )
        end

      :error ->
        {:error, {:unterminated_output, start_pos}}
    end
  end

  defp open_tag(strip_left, rest, state, start_pos) do
    case extract_tag_until(rest, state) do
      {:ok, raw_content, strip_right, remaining, state} ->
        content = String.trim(raw_content)
        dispatch_tag(content, strip_left, strip_right, remaining, state, start_pos)

      :error ->
        {:error, {:unterminated_tag, start_pos}}
    end
  end

  defp dispatch_tag("comment", _strip_left, _strip_right, remaining, state, start_pos) do
    case scan_until_end_tag(remaining, "endcomment", state) do
      {:ok, _discarded, remaining, state} -> do_tokenize(remaining, state)
      :error -> {:error, {:unterminated_comment, start_pos}}
    end
  end

  defp dispatch_tag("raw", _strip_left, _strip_right, remaining, state, start_pos) do
    raw_start_pos = position(state)

    case scan_until_end_tag(remaining, "endraw", state) do
      {:ok, "", remaining, state} ->
        do_tokenize(remaining, state)

      {:ok, raw_text, remaining, state} ->
        do_tokenize(remaining, push(state, {:text, raw_text, raw_start_pos}))

      :error ->
        {:error, {:unterminated_raw, start_pos}}
    end
  end

  defp dispatch_tag(content, strip_left, strip_right, remaining, state, start_pos) do
    do_tokenize(remaining, push(state, {:tag, content, strip_left, strip_right, start_pos}))
  end

  defp extract_output_until(input, state), do: extract_output_until(input, state, [])

  defp extract_output_until("-}}" <> rest, state, acc) do
    {:ok, iodata_to_content(acc), true, rest, advance(state, 3)}
  end

  defp extract_output_until("}}" <> rest, state, acc) do
    {:ok, iodata_to_content(acc), false, rest, advance(state, 2)}
  end

  defp extract_output_until("", _state, _acc), do: :error

  defp extract_output_until(<<char::utf8, rest::binary>>, state, acc) do
    extract_output_until(rest, advance_char(state, <<char::utf8>>), [<<char::utf8>> | acc])
  end

  defp extract_tag_until(input, state), do: extract_tag_until(input, state, [])

  defp extract_tag_until("-%}" <> rest, state, acc) do
    {:ok, iodata_to_content(acc), true, rest, advance(state, 3)}
  end

  defp extract_tag_until("%}" <> rest, state, acc) do
    {:ok, iodata_to_content(acc), false, rest, advance(state, 2)}
  end

  defp extract_tag_until("", _state, _acc), do: :error

  defp extract_tag_until(<<char::utf8, rest::binary>>, state, acc) do
    extract_tag_until(rest, advance_char(state, <<char::utf8>>), [<<char::utf8>> | acc])
  end

  # Scans verbatim (without interpreting nested tags) until the literal end
  # tag `{% <end_name> %}` (or a whitespace-stripped variant) is found.
  # Used for `{% comment %}` / `{% raw %}` blocks, whose contents must not be
  # tokenized as ordinary Liquid syntax.
  defp scan_until_end_tag(input, end_name, state),
    do: scan_until_end_tag(input, end_name, state, [])

  defp scan_until_end_tag(input, end_name, state, acc) do
    case try_end_tag(input, end_name, state) do
      {:ok, remaining, state} ->
        {:ok, iodata_to_content(acc), remaining, state}

      :no ->
        case input do
          "" ->
            :error

          <<char::utf8, rest::binary>> ->
            scan_until_end_tag(rest, end_name, advance_char(state, <<char::utf8>>), [
              <<char::utf8>> | acc
            ])
        end
    end
  end

  defp try_end_tag("{%-" <> rest, end_name, state),
    do: match_end_tag_body(rest, end_name, advance(state, 3))

  defp try_end_tag("{%" <> rest, end_name, state),
    do: match_end_tag_body(rest, end_name, advance(state, 2))

  defp try_end_tag(_input, _end_name, _state), do: :no

  defp match_end_tag_body(rest, end_name, state) do
    case extract_tag_until(rest, state) do
      {:ok, raw_content, _strip_right, remaining, state} ->
        if String.trim(raw_content) == end_name do
          {:ok, remaining, state}
        else
          :no
        end

      :error ->
        :no
    end
  end

  defp iodata_to_content(acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp position(%State{line: line, col: col}), do: %{line: line, col: col}

  defp advance(%State{col: col} = state, n), do: %{state | col: col + n}

  defp advance_char(%State{line: line} = state, "\n"), do: %{state | line: line + 1, col: 1}
  defp advance_char(%State{col: col} = state, _char), do: %{state | col: col + 1}

  defp push(%State{tokens: tokens} = state, token), do: %{state | tokens: [token | tokens]}

  defp finish(%State{tokens: tokens}) do
    {:ok, tokens |> Enum.reverse() |> coalesce_text()}
  end

  defp coalesce_text(tokens) do
    do_coalesce_text(tokens, [])
  end

  defp do_coalesce_text([], acc) do
    Enum.reverse(acc)
  end

  defp do_coalesce_text([{:text, current, _pos} | rest], [{:text, previous, first_pos} | acc]) do
    do_coalesce_text(rest, [{:text, previous <> current, first_pos} | acc])
  end

  defp do_coalesce_text([token | rest], acc) do
    do_coalesce_text(rest, [token | acc])
  end
end

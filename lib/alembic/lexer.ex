defmodule Alembic.Lexer do
  @moduledoc """
  Convert Alembic template source into lexical tokens.
  """

  alias Alembic.Token

  @type position :: non_neg_integer()
  @type reason ::
          {:unterminated_output, position()}
          | {:unterminated_tag, position()}
          | {:empty_output_tag, position()}

  # @typep state :: %{tokens: [Token.t()], position: position()}

  @spec tokenize(String.t()) :: {:ok, [Token.t()]} | {:error, reason()}
  def tokenize(source) when is_binary(source) do
    do_tokenize(source, %{tokens: [], position: 0})
  end

  defp do_tokenize("", %{tokens: tokens}) do
    tokens = tokens |> Enum.reverse() |> coalesce_text()

    {:ok, tokens}
  end

  defp do_tokenize("{{" <> rest, %{tokens: tokens, position: position} = state) do
    case extract_until(rest, "}}") do
      {:ok, raw_content, remaining} ->
        content = String.trim(raw_content)

        if content == "" do
          {:error, {:empty_output_tag, position}}
        else
          consumed = 4 + codepoint_length(raw_content)

          do_tokenize(remaining, %{
            state
            | tokens: [{:output, content} | tokens],
              position: position + consumed
          })
        end

      :error ->
        {:error, {:unterminated_output, position}}
    end
  end

  defp do_tokenize("{%" <> rest, %{tokens: tokens, position: position} = state) do
    case extract_until(rest, "%}") do
      {:ok, raw_content, remaining} ->
        content = String.trim(raw_content)
        consumed = 4 + codepoint_length(raw_content)

        do_tokenize(remaining, %{
          state
          | tokens: [{:output, content} | tokens],
            position: position + consumed
        })

      :error ->
        {:error, {:unterminated_output, position}}
    end
  end

  defp do_tokenize(<<char::utf8, rest::binary>>, %{tokens: tokens, position: position} = state) do
    do_tokenize(rest, %{
      state
      | tokens: [{:text, <<char::utf8>>} | tokens],
        position: position + 1
    })
  end

  defp extract_until(input, delimiter) do
    extract_until(input, delimiter, [])
  end

  defp extract_until("}}" <> rest, "}}", acc) do
    content = acc |> Enum.reverse() |> IO.iodata_to_binary()

    {:ok, content, rest}
  end

  defp extract_until("%}" <> rest, "%}", acc) do
    content = acc |> Enum.reverse() |> IO.iodata_to_binary()

    {:ok, content, rest}
  end

  defp extract_until("", _, _) do
    :error
  end

  defp extract_until(<<char::utf8, rest::binary>>, delimiter, acc) do
    extract_until(rest, delimiter, [<<char::utf8>> | acc])
  end

  defp codepoint_length(binary) do
    codepoint_length(binary, 0)
  end

  defp codepoint_length("", count), do: count

  defp codepoint_length(<<_char::utf8, rest::binary>>, count) do
    codepoint_length(rest, count + 1)
  end

  defp coalesce_text(tokens) do
    do_coalesce_text(tokens, [])
  end

  defp do_coalesce_text([], acc) do
    Enum.reverse(acc)
  end

  defp do_coalesce_text([{:text, current} | rest], [{:text, previous} | acc]) do
    do_coalesce_text(rest, [{:text, previous <> current} | acc])
  end

  defp do_coalesce_text([token | rest], acc) do
    do_coalesce_text(rest, [token | acc])
  end
end

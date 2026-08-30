defmodule Alembic.LexerGenerators do
  @moduledoc false

  @text_chars ~w(a b c 1 2 3 space Olá こんにちは 👋)a
  @word_chars ~w(a b c d e name user index)

  @spec random_canonical_template() :: String.t()
  def random_canonical_template do
    1..Enum.random(0..6)//1
    |> Enum.map_join(fn _ -> random_segment() end)
  end

  @spec reconstruct([Alembic.Token.t()]) :: String.t()
  def reconstruct(tokens) do
    tokens
    |> Enum.map(&reconstruct_token/1)
    |> IO.iodata_to_binary()
  end

  defp reconstruct_token({:text, content, _pos}), do: content

  defp reconstruct_token({:output, content, strip_left, strip_right, _pos}) do
    open = if strip_left, do: "{{-", else: "{{"
    close = if strip_right, do: "-}}", else: "}}"
    open <> " " <> content <> " " <> close
  end

  defp reconstruct_token({:tag, content, strip_left, strip_right, _pos}) do
    open = if strip_left, do: "{%-", else: "{%"
    close = if strip_right, do: "-%}", else: "%}"
    open <> " " <> content <> " " <> close
  end

  defp random_segment do
    case Enum.random([:text, :output, :tag]) do
      :text -> random_text()
      :output -> random_delimited("{{", "}}")
      :tag -> random_delimited("{%", "%}")
    end
  end

  defp random_text do
    char_count = Enum.random(1..5)

    1..char_count
    |> Enum.map_join(fn _ -> random_text_char() end)
  end

  defp random_text_char do
    case Enum.random(@text_chars) do
      :space -> " "
      atom -> Atom.to_string(atom)
    end
  end

  defp random_delimited(open, close) do
    strip_left = Enum.random([true, false])
    strip_right = Enum.random([true, false])
    content = Enum.random(@word_chars)

    open_marker = if strip_left, do: open <> "-", else: open
    close_marker = if strip_right, do: "-" <> close, else: close

    open_marker <> " " <> content <> " " <> close_marker
  end
end

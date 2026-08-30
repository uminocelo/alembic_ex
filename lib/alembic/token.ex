defmodule Alembic.Token do
  @moduledoc """
  The three token classes `Alembic.Lexer.tokenize/1` produces.

  | Token | Shape | Example input |
  |---|---|---|
  | Raw text | `{:text, string, position}` | `Hello, world!` |
  | Output tag | `{:output, string, strip_left, strip_right, position}` | `{{ user.name }}` |
  | Block tag | `{:tag, string, strip_left, strip_right, position}` | `{% if user.admin %}` |

      # Produced by Alembic.Lexer.tokenize/1
      {:text, "Hello, ", %{line: 1, col: 1}}
      {:output, "user.name", false, false, %{line: 1, col: 8}}
      {:tag, "if user.admin", false, false, %{line: 1, col: 20}}

  `strip_left`/`strip_right` come from dash-modified delimiters (`{{-`,
  `-}}`, `{%-`, `-%}`) — see `Alembic.Lexer`. `Alembic.Parser` resolves
  them immediately, trimming adjacent `:text` tokens before building the
  AST, so no downstream stage ever needs to look at these flags again.

  `position` is the 1-indexed line/column of the token's first character
  (the opening delimiter for `:output`/`:tag`; the first character of the
  run for `:text`). It travels with the token so `Alembic.Parser` can
  attach a location to errors that reference a specific token (e.g.
  `:unexpected_token`), without needing its own separate position tracking.
  """

  @type position :: %{line: pos_integer(), col: pos_integer()}

  @type t ::
          {:text, String.t(), position()}
          | {:output, String.t(), boolean(), boolean(), position()}
          | {:tag, String.t(), boolean(), boolean(), position()}

  @doc """
  Returns the position of any token, regardless of its shape.

  ## Examples

      iex> Alembic.Token.position({:text, "hi", %{line: 1, col: 1}})
      %{line: 1, col: 1}

      iex> Alembic.Token.position({:tag, "endif", false, false, %{line: 3, col: 5}})
      %{line: 3, col: 5}
  """
  @spec position(t()) :: position()
  def position({:text, _content, pos}), do: pos
  def position({:output, _content, _sl, _sr, pos}), do: pos
  def position({:tag, _content, _sl, _sr, pos}), do: pos
end

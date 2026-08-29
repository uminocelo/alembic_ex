defmodule Alembic.Token do
  @moduledoc """
  The three token classes `Alembic.Lexer.tokenize/1` produces.

  | Token | Shape | Example input |
  |---|---|---|
  | Raw text | `{:text, string}` | `Hello, world!` |
  | Output tag | `{:output, string, strip_left, strip_right}` | `{{ user.name }}` |
  | Block tag | `{:tag, string, strip_left, strip_right}` | `{% if user.admin %}` |

      # Produced by Alembic.Lexer.tokenize/1
      {:text, "Hello, "}
      {:output, "user.name | upcase", false, false}
      {:tag, "if user.admin", false, false}
      {:tag, "endif", false, false}

  `strip_left`/`strip_right` come from dash-modified delimiters (`{{-`,
  `-}}`, `{%-`, `-%}`) — see `Alembic.Lexer`. `Alembic.Parser` resolves
  them immediately, trimming adjacent `:text` tokens before building the
  AST, so no downstream stage ever needs to look at these flags again.
  """

  @type t ::
          {:text, String.t()}
          | {:output, String.t(), boolean(), boolean()}
          | {:tag, String.t(), boolean(), boolean()}
end

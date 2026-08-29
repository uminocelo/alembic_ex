defmodule Alembic.AST do
  @moduledoc """
  The abstract syntax tree `Alembic.Parser` produces and `Alembic.Evaluator`
  walks. Every node is a tagged tuple, chosen over structs so pattern
  matching in the evaluator stays exhaustive — adding a node type without
  handling it produces a compiler warning, not a silent no-op.

  This is the **AST**, not the **CST** (concrete syntax tree): it discards
  punctuation (`{{`, `}}`, `%}`, `endif`, dash whitespace markers) and keeps
  only semantically meaningful structure. See `docs/grammar.md` for a
  worked example showing both representations of the same template.

  ## Node catalog

  | Node | Shape | Example source |
  |---|---|---|
  | `text_node()` | `{:text, content}` | `Hello, ` |
  | `output_node()` | `{:output, path, filters}` | `{{ user.name \\| upcase }}` |
  | `if_node()` | `{:if, cond, then, elsifs, else}` | `{% if x %}...{% endif %}` |
  | `for_node()` | `{:for, var, iterable, body, else}` | `{% for i in xs %}...{% endfor %}` |
  | `assign_node()` | `{:assign, var, expr}` | `{% assign x = 1 %}` |
  | `extends_node()` | `{:extends, name}` | `{% extends "base.html" %}` |
  | `block_node()` | `{:block, name, body}` | `{% block title %}...{% endblock %}` |
  | `include_node()` | `{:include, name, vars}` | `{% include "header.html" %}` |

  ## Worked example

  `{{ user.name | upcase }}` maps to:

      {:output, ["user", "name"], [{:filter, "upcase", []}]}

  A non-trivial template:

      {% extends "base.html" %}
      {% block content %}
        Hello, {{ user.name | upcase }}!
        {% if user.admin %}(admin){% endif %}
      {% endblock %}

  parses to:

      [
        {:extends, "base.html"},
        {:block, "content", [
          {:text, "\\n  Hello, "},
          {:output, ["user", "name"], [{:filter, "upcase", []}]},
          {:text, "!\\n  "},
          {:if, {:variable, ["user", "admin"]}, [{:text, "(admin)"}], [], nil},
          {:text, "\\n"}
        ]}
      ]

  ## Expression nodes (`expr()`)

  | Node | Shape | Example |
  |---|---|---|
  | `{:variable, path}` | variable path | `user.name` → `{:variable, ["user", "name"]}` |
  | `{:literal, value}` | literal | `42` → `{:literal, 42}` |
  | `{:filter_chain, base, filters}` | filtered expression | `x \\| upcase` |
  | `{:compare, op, left, right}` | comparison | `x > 0` |
  | `{:logical, op, left, right}` | `and`/`or` | `a and b` |
  | `{:not, expr}` | negation | `not x` |

  Output tags (`output_node()`) require a bare variable-path base,
  optionally wrapped in a filter chain — a literal base like
  `{{ "hi" | upcase }}` is rejected by `Alembic.Parser` with
  `{:unsupported_output_expression, _}` (a constraint fixed by this
  module's shape since Milestone 1.1, before the parser existed).
  """

  @type path :: [String.t()]
  @type literal :: String.t() | number() | boolean() | nil
  @type compare_op :: :eq | :neq | :gt | :lt | :gte | :lte | :contains
  @type logical_op :: :and | :or
  @type expr ::
          {:variable, path()}
          | {:literal, literal()}
          | {:filter_chain, expr(), [filter()]}
          | {:compare, compare_op(), expr(), expr()}
          | {:logical, logical_op(), expr(), expr()}
          | {:not, expr()}
  @type filter :: {:filter, String.t(), [expr()]}
  @type text_node :: {:text, String.t()}
  @type output_node :: {:output, path(), [filter()]}
  @type if_node :: {:if, expr(), [ast_node()], [{expr(), [ast_node()]}], [ast_node()] | nil}
  @type for_node :: {:for, String.t(), expr(), [ast_node()], [ast_node()] | nil}
  @type assign_node :: {:assign, String.t(), expr()}
  @type extends_node :: {:extends, String.t()}
  @type block_node :: {:block, String.t(), [ast_node()]}
  @type include_node :: {:include, String.t(), map()}
  @type ast_node ::
          text_node()
          | output_node()
          | if_node()
          | for_node()
          | assign_node()
          | extends_node()
          | block_node()
          | include_node()
  @type t :: [ast_node()]
end

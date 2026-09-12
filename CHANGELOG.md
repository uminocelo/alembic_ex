# Changelog

All notable changes to this project are documented in this file, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.2.0] - 2026-09-12

### Added

- **Loop control** — `{% break %}` and `{% continue %}` inside a
  `{% for %}` body (parse errors anywhere else); `{% break %}` exits only
  the innermost loop.
- **Cycle** — `{% cycle "a", "b" %}` round-robins its values on each render,
  and `{% cycle "rows": "a", "b" %}` shares state across same-named groups.
- **Range iterables** — `{% for i in (1..5) %}` with integer or variable
  endpoints. Descending ranges iterate zero times and trigger `{% else %}`,
  matching Liquid rather than Elixir's descending ranges.
- **Capture** — `{% capture x %}...{% endcapture %}` renders its body into a
  flattened string stored in `x`, with the same visibility as `{% assign %}`.
- **Unless** — `{% unless expr %}` / `{% else %}` / `{% endunless %}`,
  desugared by the parser to a negated `{% if %}`. `{% elsif %}` inside an
  unless is a parse error, matching Liquid.
- **Case/when** — `{% case subject %}` with `{% when a, b, c %}` (multiple
  values per when) and an optional `{% else %}`, terminated by
  `{% endcase %}`. Matching reuses the evaluator's `==` semantics, so
  `{% when empty %}` works.
- **`empty` / `blank` keywords** — contextual comparison operands
  (`x == empty`, `x != blank`, either operand order). `empty` matches `""`,
  `[]`, and `%{}` (`nil` is *not* empty); `blank` also matches `nil`,
  `false`, and whitespace-only strings. They are equality-only: other
  operators raise `{:keyword_requires_equality, _, _}`.
- **Dynamic bracket access** — `items[key]`, `a[b.c]`, and
  `items[forloop.index0]` evaluate the bracketed expression against the
  current context before lookup. A segment resolving to anything other than
  a string or integer is a render error; strict mode reports the fully
  resolved path.
- **`{% render %}`** — `{% render "card.html" %}` and
  `{% render "card.html", title: post.title %}` render a partial in an
  *isolated* scope: only the explicitly passed variables are visible, parent
  scopes/assigns never leak in, and the partial's own assignments do not leak
  out. `loader_fn`, `strict`, and `custom_filters` still carry over from the
  parent. The `for ... as` variant is not supported.
- **Literal output bases** — output tags now accept a literal or a filter
  chain over a literal/variable, so `{{ 42 }}`, `{{ "hi" }}`, and
  `{{ "hi" | upcase }}` render. Comparison/logical bases (`{{ x > 1 }}`)
  remain rejected.

### Changed

- **`slice` now slices arrays as well as strings**, removing a documented
  deviation from upstream Liquid. Positive and negative start offsets are
  supported, with or without a length; an out-of-range start returns `[]`
  for arrays and `""` for strings. Existing string behavior is unchanged.
- Output nodes are now `{:output, expr}` rather than
  `{:output, path, filters}`, so the base can be a variable, a literal, or a
  filter chain. This is an AST-level change; callers constructing output
  nodes directly must update. `{{ block.super }}` is now
  `{:output, {:variable, ["block", "super"]}}`.
- `COMPATIBILITY.md`, `docs/grammar.md`, and the AST moduledoc document the
  new tags, keywords, and output-base rules; the `slice` and output-base
  deviation rows are removed.

## [0.1.1] - 2026-09-06

### Changed

- Removed all Grimoire references from `README.md`, `examples/README.md`,
  `lib/alembic.ex`, and `test/integration/pipeline_test.exs`. Alembic is
  documented as a standalone library; Grimoire remains a downstream consumer
  but is no longer mentioned in the package itself.
- Added `AGENTS.md` to guide AI agents working in this repository.

## [0.1.0] - 2026-08-29

### Added

- **Lexer** (`Alembic.Lexer`) — recursive binary-pattern-matching tokenizer;
  text/output/tag tokens, each carrying a `line`/`col` position
  (`Alembic.Token.position/1`); whitespace control (`{{-`, `-}}`, `{%-`,
  `-%}`); `{% comment %}` and `{% raw %}` blocks; UTF-8 correct; structured
  errors with line/column positions.
- **Parser** (`Alembic.Parser`, `Alembic.Parser.Expression`) — recursive
  descent parser producing `Alembic.AST.t()`; full expression grammar
  (variable paths, literals, comparison/logical operators with `not > and
  > or` precedence, filter chains); `{% if %}`/`{% elsif %}`/`{% else %}`,
  `{% for %}`/`{% else %}`, `{% assign %}`, `{% extends %}`/`{% block %}`,
  `{% include %}`. `parse/1` reports the first error found;
  `{:unexpected_token, token, position}` and `{:missing_end_tag, tag_name,
  position}` (the position of the *opening* tag, since a missing close
  often means there's no closing tag anywhere to point at) both carry a
  location. `parse_all/1` instead keeps going after an error — best-effort
  skip-to-next-tag-or-output recovery — to report every independent
  problem found in one pass, returning `{:ok, ast}` or
  `{:error, [reason(), ...]}`.
- **Evaluator** (`Alembic.Evaluator`) — tree-walking interpreter with
  iolist output accumulation; Liquid truthiness (`0`/`""`/`[]` truthy, only
  `nil`/`false` falsy); `{% assign %}` visible to every later node at the
  same level, including across `{% for %}`/`{% if %}` boundaries and
  across an `{% include %}` boundary; optional `strict: true` mode erroring
  on undefined variables.
- **Context** (`Alembic.Context`) — scoped symbol table; `push_scope/2` /
  `pop_scope/1`; dot/bracket path resolution across maps, keyword lists,
  and list indices; `forloop` metadata.
- **Filters** (`Alembic.Filters`, `Alembic.Filter`) — full built-in string,
  array, number, and misc filter catalog, each with type-coercion behavior
  documented in `Alembic.Filters`' moduledoc (a reference table, since the
  individual filter clauses are private and can't carry their own `@doc`);
  custom filter registration globally via
  `config :alembic, custom_filters: [...]` or per call via `render/3`'s
  `custom_filters:` option (per-call modules take precedence on a name
  collision).
- **Template inheritance** (`Alembic.Inheritance`) — multi-level
  `{% extends %}` chains, `{{ block.super }}`, circular- and
  max-depth-inheritance detection.
- **File loader** (`Alembic.Loader`) — multi-root resolution, automatic
  extension appending, path-traversal protection.
- **Cache** (`Alembic.Cache`) — ETS-backed compiled-template cache keyed by
  `{path, mtime}`; concurrent lock-free reads; `sweep/0` for pruning stale
  entries; `cache: false` per-call bypass; the ETS table is recreated
  automatically if the cache's GenServer is ever restarted by its
  supervisor.
- **Public API** (`Alembic`) — `compile/2`, `render/3`, `render_string/3`,
  `render_file/3`, and `!` variants wired through the full pipeline;
  `Alembic.TemplateError`, `Alembic.CompileError`, `Alembic.RenderError`.
- `docs/grammar.md` — formal EBNF grammar, LL(1) analysis, worked parse
  tree, and documented grammar ambiguity resolutions.
- `COMPATIBILITY.md` — supported/deviating/unsupported/extension features
  relative to upstream Liquid (including that `slice` operates on strings
  only, not arrays).
- `BENCHMARKS.md` — lexer, full-pipeline, cache hit/miss, iolist-vs-concat,
  and filter-chain benchmarks, including a documented finding that
  `{% include %}` partials are recompiled on every render, uncached,
  independent of the outer template's cache status.

### Notes

- Zero runtime dependencies — `ex_doc`, `credo`, `dialyxir`, and `benchee`
  are all `dev`/`test`-only.
- Test suite: 448 tests + 62 doctests, 91.15% coverage, `mix credo --strict`
  and `mix dialyzer` both clean.

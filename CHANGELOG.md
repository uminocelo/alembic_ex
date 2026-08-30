# Changelog

All notable changes to this project are documented in this file, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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

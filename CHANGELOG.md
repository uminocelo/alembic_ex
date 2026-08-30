# Changelog

All notable changes to this project are documented in this file, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- `Alembic.Parser.parse_all/1` — like `parse/1`, but keeps parsing past an
  error instead of stopping at the first one, so one call can report every
  independent problem in a template. Returns `{:ok, ast}` when there are
  zero errors (identical to `parse/1`), or `{:error, [reason(), ...]}`
  otherwise. Recovery is best-effort: on an error, it skips forward to the
  next `{% tag %}` or `{{ output }}` token and resumes from there, so a
  single badly broken construct can occasionally surface more than one
  reported error. Added as a new function rather than changing `parse/1`'s
  return shape, to avoid a breaking change to `Alembic.compile/2` and every
  existing caller that pattern-matches `parse/1`'s single-`reason`
  `{:error, reason}` shape.

### Changed

- `Alembic.Token.t()` now carries a `line`/`col` position on every token
  (`Alembic.Token.position/1` extracts it from any shape). `Alembic.Parser`'s
  `{:unexpected_token, ...}` error surfaces it as `{:unexpected_token, token,
  %{line:, col:}}`. Also fixed a `.formatter.exs` typo (`line_lenght` →
  `line_length`) that had silently disabled the 100-column format setting.
- `Alembic.Filters`' `@moduledoc` now documents type-coercion behavior for
  every built-in filter (a "Type coercion reference" section, since the
  individual filter clauses are private and can't carry their own `@doc`).
  This surfaced a real, previously undocumented deviation from upstream
  Liquid — `slice` only ever operates on strings, not arrays — now recorded
  in `COMPATIBILITY.md`. `test/alembic/filters_test.exs` also gained a
  second test case (happy path + edge case) for every filter that only had
  one.
- `:custom_filters` is now a real per-call option on `Alembic.render/3` (and
  `render_string/3`/`render_file/3`), not just global `config :alembic,
  custom_filters: [...]` — per-call modules take precedence on a name
  collision. `Alembic.Context` gained a `custom_filters` field
  (`Context.custom_filters/2`) and `Alembic.Filters.apply/4` accepts a
  per-call module list.
- `Alembic.Cache` gained a supervisor-restart test confirming the ETS table
  comes back empty (not just alive) after the `one_for_one` supervisor
  restarts a crashed `Alembic.Cache` process. Its `Logger.debug/1` calls now
  use the lazy `fn -> ... end` form so the log message is only built when
  it will actually be emitted.
- `{% assign %}` visibility across an `{% include %}` boundary now has a
  dedicated integration test.
- `BENCHMARKS.md` numbers refreshed; the pipeline benchmark fixture gained
  5 `{% include %}` tags it was missing (it had none), which surfaced a
  real finding: `Alembic.Evaluator`'s internal include-compilation step
  recompiles every include on every render, uncached, regardless of the
  outer template's cache status — documented in the "Cache: hit vs miss"
  section rather than fixed (caching partials is a feature change, out of
  scope here).

## [0.1.0] - 2026-08-29

### Added

- **Lexer** (`Alembic.Lexer`) — recursive binary-pattern-matching tokenizer;
  text/output/tag tokens; whitespace control (`{{-`, `-}}`, `{%-`, `-%}`);
  `{% comment %}` and `{% raw %}` blocks; UTF-8 correct; structured errors
  with line/column positions.
- **Parser** (`Alembic.Parser`, `Alembic.Parser.Expression`) — recursive
  descent parser producing `Alembic.AST.t()`; full expression grammar
  (variable paths, literals, comparison/logical operators with `not > and
  > or` precedence, filter chains); `{% if %}`/`{% elsif %}`/`{% else %}`,
  `{% for %}`/`{% else %}`, `{% assign %}`, `{% extends %}`/`{% block %}`,
  `{% include %}`.
- **Evaluator** (`Alembic.Evaluator`) — tree-walking interpreter with
  iolist output accumulation; Liquid truthiness (`0`/`""`/`[]` truthy, only
  `nil`/`false` falsy); `{% assign %}` visible to every later node at the
  same level, including across `{% for %}`/`{% if %}` boundaries; optional
  `strict: true` mode erroring on undefined variables.
- **Context** (`Alembic.Context`) — scoped symbol table; `push_scope/2` /
  `pop_scope/1`; dot/bracket path resolution across maps, keyword lists,
  and list indices; `forloop` metadata.
- **Filters** (`Alembic.Filters`, `Alembic.Filter`) — full built-in string,
  array, number, and misc filter catalog; custom filter registration via
  `config :alembic, custom_filters: [...]`.
- **Template inheritance** (`Alembic.Inheritance`) — multi-level
  `{% extends %}` chains, `{{ block.super }}`, circular- and
  max-depth-inheritance detection.
- **File loader** (`Alembic.Loader`) — multi-root resolution, automatic
  extension appending, path-traversal protection.
- **Cache** (`Alembic.Cache`) — ETS-backed compiled-template cache keyed by
  `{path, mtime}`; concurrent lock-free reads; `sweep/0` for pruning stale
  entries; `cache: false` per-call bypass.
- **Public API** (`Alembic`) — `compile/2`, `render/3`, `render_string/3`,
  `render_file/3`, and `!` variants wired through the full pipeline;
  `Alembic.TemplateError`, `Alembic.CompileError`, `Alembic.RenderError`.
- `docs/grammar.md` — formal EBNF grammar, LL(1) analysis, worked parse
  tree, and documented grammar ambiguity resolutions.
- `COMPATIBILITY.md` — supported/deviating/unsupported/extension features
  relative to upstream Liquid.
- `BENCHMARKS.md` — lexer, full-pipeline, cache hit/miss, iolist-vs-concat,
  and filter-chain benchmarks.

### Notes

- Zero runtime dependencies — `ex_doc`, `credo`, `dialyxir`, and `benchee`
  are all `dev`/`test`-only.
- Test suite: 374 tests + 55 doctests, ~90% coverage, `mix credo --strict`
  and `mix dialyzer` both clean.

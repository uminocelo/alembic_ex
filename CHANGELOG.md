# Changelog

All notable changes to this project are documented in this file, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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

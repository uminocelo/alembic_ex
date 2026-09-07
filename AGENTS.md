# AGENTS.md

Guide for AI agents working in this repository. Alembic is an independent
Liquid-compatible template engine for Elixir, with **zero runtime dependencies**.

## Essential commands

```bash
mix deps.get                    # install dependencies
mix test                        # full suite: unit + integration + doctests
mix test --cover                # with coverage report
mix test path/to/file_test.exs  # single test file
mix test --only describe:"..."  # single describe block
mix format --check-formatted    # formatting check (CI enforces this)
mix format                      # auto-format
mix compile --warnings-as-errors  # compile, warnings as errors (CI)
MIX_ENV=test mix compile --warnings-as-errors  # test env compile (CI)
mix credo --strict              # static analysis, strict mode (CI)
mix dialyzer                    # type checking (CI; slow first run, cached after)
mix docs                        # generate ExDoc HTML
mix hex.build                   # build the Hex package locally
mix run bench/lexer_bench.exs   # run a benchmark (see BENCHMARKS.md)
```

CI (`.github/workflows/ci.yml`) runs all of: format check, both compiles,
`mix test`, `mix credo --strict`, `mix dialyzer`, `mix hex.build`. A PR is not
merge-ready unless every one passes.

**Credo is strict**: `.credo.exs` sets `strict: true`, so `mix credo` alone
already enables low-priority checks — `--strict` is belt-and-suspenders. TODOs
cause a non-zero exit (`exit_status: 2`); FIXMEs warn. Max line length is 120
(low priority).

**Test env warnings are errors**: `mix.exs` sets
`elixirc_options(:test)` to `[warnings_as_errors: true]`, so the test-env
compile fails on any compiler warning. Use `MIX_ENV=test mix compile` when
checking test-only modules.

## Project layout

```
lib/alembic.ex            # Public API: compile/render/render_string/render_file (+ bang variants)
lib/alembic/
  application.ex          # OTP app callback: supervises Alembic.Cache
  lexer.ex                # Source → tokens (recursive binary pattern matching)
  token.ex                # Token type + position helper
  parser.ex               # Tokens → AST (recursive descent); whitespace control resolved here
  parser/expression.ex    # Expression sub-grammar (filters, comparisons, logical ops)
  ast.ex                  # AST node types (@type specs + moduledoc catalog)
  evaluator.ex            # AST + Context → rendered string (iolist accumulation)
  context.ex              # Scoped symbol table (stack of maps + assigns)
  filters.ex              # Built-in Liquid filter library (private clauses)
  filter.ex               # Filter behaviour (name/0, apply/2)
  inheritance.ex          # {% extends %}/{% block %} two-pass resolution
  loader.ex               # Template name → file path resolution + read
  cache.ex                # ETS-backed compiled-AST cache (GenServer + :public ETS)
  config.ex               # Application config reader/validator
docs/grammar.md           # Formal EBNF grammar (authoritative)
test/                     # Unit + integration + property tests
test/support/             # Test helpers (compiled in test env via elixirc_paths)
bench/                    # Benchee benchmarks (dev-only, not CI)
examples/                 # Runnable .exs examples
config/                   # config.exs + dev/test/prod overrides
```

`mix.exs` groups the modules in `docs/`: **Pipeline** (Lexer → Token → Parser
→ AST → Evaluator), **Runtime** (Context, Filters, Filter, Inheritance),
**Infrastructure** (Loader, Cache, Config, Application), **Errors**
(TemplateError, CompileError, RenderError).

## Architecture and data flow

The render pipeline is documented in `lib/alembic.ex`'s moduledoc. The
one-line summary:

```
source → Lexer.tokenize → Parser.parse → [Inheritance.preprocess] → Evaluator.eval → String
```

Key properties an agent must internalize:

- **compile/render separation is deliberate.** `compile/2` returns an AST a
  caller can cache and reuse across many `render/3` calls with different
  assigns. `render_file/3` is the one place that bothers with the ETS cache
  internally; `render/3` does not.
- **Whitespace control is resolved at parse time, not eval time.** `Parser`
  runs `apply_whitespace_control/1` over the token list *before* building any
  AST node. The AST has no `strip_left`/`strip_right` fields. Do not add them.
- **Inheritance is a preprocess pass, not an evaluator concern.**
  `Inheritance.preprocess/2` runs before `Evaluator.eval/2` and splices every
  `{:block, _, _}` away — the Evaluator has no `:block` clause. `{% extends %}`
  and `{:extends, _}` nodes also never reach the evaluator.
- **`{% assign %}` threads context through the fold.** `eval_nodes/2` is an
  `Enum.reduce_while/3`, not `Enum.map/2`, so an assign is visible to every
  *later* sibling node, including across `{% for %}`/`{% if %}` and `{% include %}`
  boundaries.
- **Output is an iolist, flattened once.** `Evaluator` accumulates nested
  lists/binaries and calls `IO.iodata_to_binary/1` once at the end. Do not
  use `<>` to build output in the evaluator — it's O(n²).
- **Cache: GenServer for writes, direct ETS for reads.** `Cache.get/1` does
  `:ets.lookup/2` (bypasses the mailbox); `put/2`/`invalidate/1`/`clear/0`
  are casts through the GenServer. `sweep/0` is a call. The ETS table is owned
  by the GenServer; `Alembic.Application`'s `one_for_one` supervisor
  recreates it on crash.
- **Cache key is `{path, mtime}`.** A modified file is automatically a miss —
  no explicit invalidation needed for source edits.
- **Loader is path-traversal-safe and TOCTOU-safe.** It calls `File.read/1`
  directly on candidate paths, never `File.exists?/1` first. Multiple roots
  are checked in order, first match wins. Extensions are auto-appended when
  a name has none.
- **Includes share the including template's scope** (classic `include`
  semantics), not isolated `render` semantics. The included template is *not*
  run through `Inheritance.preprocess/2` — a partial is not expected to use
  `extends`/`block`.

## Conventions

- **AST nodes are tagged tuples, not structs.** This is intentional: it keeps
  pattern matching in the evaluator exhaustive. Adding a node type without
  handling it produces a compiler warning, not a silent no-op. When adding a
  node, update both `AST`'s `@type` and every `eval_node/2` / parser clause.
- **Errors are tagged tuples** shaped `{:error, reason}` where `reason` is a
  tagged tuple (e.g. `{:lexer, {:unterminated_output, %{line: 1, col: 1}}}`).
  Every public function has a bang (`!`) variant that raises
  `Alembic.TemplateError`. `CompileError`/`RenderError` exist for narrower
  `rescue` clauses but are *not* raised by the bang API.
- **Token positions are 1-indexed `{line, col}`** carried inside the token.
  `Token.position/1` extracts it regardless of token shape. Error reasons that
  reference a token (`:unexpected_token`, `:missing_end_tag`) carry the
  *opening* tag's position when the closing tag is absent.
- **Moduledocs are heavy and intentional.** Every module's `@moduledoc` is
  the primary design doc — it explains *why* the module deviates from a naive
  reading of its originating issue. Read the moduledoc before editing a module.
- **Doctests are real tests.** `doctest Alembic` and per-module `doctest`
  calls run as part of `mix test`. The `Alembic.DocTest.Shout` filter module
  in `test/support/doctest_shout.ex` exists specifically so a doctest in
  `Alembic`'s moduledoc can demonstrate the `custom_filters:` option.
- **Filters are private function clauses.** `Alembic.Filters` documents each
  filter's type coercion in a table in its moduledoc, because private clauses
  can't carry `@doc`. When adding a filter, add it to both the table and the
  `apply_builtin/3` clauses.
- **No `:telemetry` dependency.** The cache uses `Logger.debug(fn -> ... end)`
  (zero-arity function, so interpolation only runs at the configured level)
  instead. Do not add telemetry — it violates the zero-runtime-deps policy.

## Testing approach

- **ExUnit**, `async: true` where safe (property tests use it).
- **Doctests** in public-API modules and per-module test files.
- **Unit tests** in `test/alembic/` mirror the `lib/alembic/` structure
  (`lexer_test.exs`, `parser_test.exs`, `evaluator_test.exs`, etc.).
- **Integration tests** in `test/integration/` exercise the full pipeline via
  the real `Alembic` public API — never calling internal modules directly,
  matching how a real caller would use the library.
- **Property tests** in `test/integration/property_test.exs` use hand-written
  random generators (no `StreamData`/`:proper` dependency — keeps the
  zero-runtime-deps policy; the generators live in `test/support/lexer_generators.ex`).
- **Template fixtures** live in `test/fixtures/templates/` and `test/fixtures/shared/`.
  `config/test.exs` sets `template_roots: ["test/fixtures/templates"]` so
  `render_file/3` works in tests without passing `roots:` explicitly.
- **Cache tests must not share state.** `Alembic.Cache` is a single global
  GenServer keyed by absolute path. The `unique_fixture_copy!/1` helper in
  `test/alembic_test.exs` copies a fixture into a unique temp dir per test so
  two tests rendering `base.html` don't race on the same cache entry. Use
  this pattern for any new cache-state test. Call `Alembic.Cache.sweep()`
  after a `render_file` to force the async `put/2` cast to be processed
  before a synchronous `get/1` in the same test.
- **`on_exit/1`** cleans up temp fixture dirs.

## Gotchas

- **`mix.exs` `elixirc_paths(:test)` includes `test/support`** — test support
  modules (`Alembic.ASTFixtures`, `Alembic.LexerGenerators`,
  `Alembic.DocTest.Shout`) are only compiled in the test env. They are not
  shipped in the Hex package.
- **`slice` filter is string-only**, not array-slicing (unlike upstream
  Liquid). See `COMPATIBILITY.md`.
- **`join` separator defaults to `""`**, not `" "` as in upstream Liquid.
  Documented divergence.
- **`url_encode`/`url_decode` use `URI.encode_www_form`/`URI.decode_www_form`**
  (space → `+`), not `URI.encode/1` (`%20`). Matches Liquid, not Elixir's
  default.
- **Liquid truthiness**: `0`, `""`, `[]` are all *truthy*; only `nil` and
  `false` are falsy. Don't use Elixir truthiness in the evaluator.
- **`{% extends %}` must be the first node** — `Parser` enforces this with
  the `:extends_not_first` error.
- **Output tag base must be a bare variable path** (optionally wrapped in a
  filter chain). `{{ "hi" | upcase }}` is rejected with
  `{:unsupported_output_expression, _}`. See `AST` moduledoc.
- **Dialyzer's first run is slow** (builds the PLT); subsequent runs are
  cached. Don't assume a hang — it's one-time.
- **The Hex package name differs from the OTP app name.** App is `:alembic`;
  Hex package is `alembic_template_engine`. Callers must add
  `hex: "alembic_template_engine"` to their dep tuple. This is documented in
  the README.
- **`mix.exs`'s `package()` ships only**: `lib`, `docs/grammar.md`, `LICENSE`,
  `mix.exs`, `README.md`, `CHANGELOG.md`, `COMPATIBILITY.md`. Test fixtures,
  benchmarks, examples, and config files are *not* in the published package.
  Do not assume a downstream caller has access to them.

## Configuration

All config is read via `Alembic.Config` (which wraps
`Application.get_env(:alembic, ...)`). Every key has both a global config form
and a per-call option override:

| Key | Default | Per-call option |
|---|---|---|
| `:template_roots` | `[]` | `:roots` |
| `:template_extensions` | `[".html", ".liquid"]` | `:extensions` |
| `:cache` | `true` | `:cache` |
| `:custom_filters` | `[]` | `:custom_filters` |
| `:max_inheritance_depth` | `10` | — |
| `:strict` (render only) | `false` | `:strict` |

Per-call `:custom_filters` modules are tried *before* globally-registered ones
on a name collision. `Alembic.Config.validate!/0` runs at application start.

## Reference documents

- `docs/grammar.md` — authoritative EBNF grammar; supersedes any issue sketch.
- `COMPATIBILITY.md` — what Alembic supports vs. deviates from vs. leaves out
  of upstream Liquid. Read this before adding "Liquid-compatible" features.
- `BENCHMARKS.md` — benchmark numbers (documentation, not tests; not in CI).
- `CHANGELOG.md` — follows [Keep a Changelog](https://keepachangelog.com).
- Each module's `@moduledoc` — the primary design doc for that module,
  including deviations from the originating issue and *why*.

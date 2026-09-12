# Code Review Skill — Alembic

Systematic review guide for PRs and changes in the Alembic template engine.
Baseline: `AGENTS.md`, `.credo.exs` (strict), `.formatter.exs` (line_length: 100),
CI pipeline (`.github/workflows/ci.yml`).

---

## Pre-flight: verify CI passes

Before reviewing logic, confirm the automated gates are green:

```
mix format --check-formatted
mix compile --warnings-as-errors
MIX_ENV=test mix compile --warnings-as-errors
mix test
mix credo --strict
mix dialyzer
```

A non-green CI means the review should focus on fixing CI first.

---

## 1. DRY

### 1.1 Duplicate logic

- **Step functions** (`lexer_step`, `parser_step`, etc.) are the canonical
  reuse surface. If a new pipeline stage is added, it should follow the
  same `{:ok, _} | {:error, {:domain, reason}}` shape and be wired through
  a `_step` function — not inlined into `compile/2` or `render_file/3`.

- **Parser helpers** (`expect_tag/3`, `parse_optional_else/2`,
  `parse_elsifs/2`, `parse_case_whens/3`) are shared across if/for/case/
  unless/block/capture. New tag constructs should reuse these, not reimplement
  the scanning loop.

- **Evaluator folds** all follow `Enum.reduce_while/3` + `case` +
  `{:cont, {:ok, [v | acc]}}`. If a new reduction is needed, match the
  existing shape exactly — don't introduce a new accumulator convention.

- **Filter coercion** (`coerce_to_string/1`, `coerce_to_number/1`,
  `truthy?/1`, `blank?/1`) is the single source of truth for type
  handling. New filters must use these helpers, not inline coercion.

- **Loader resolution** is a single closure factory (`Loader.build_loader/1`).
  New template-loading paths must inject a loader function, not duplicate
  `File.read/1` calls.

### 1.2 Structural duplication

- Private helpers across modules that do the same binary scan, list
  reversal, or position extraction should be flagged. `Token.position/1`
  is the canonical example — position extraction never appears inline.

- Test helpers (`parse/1`, `render/1..2`, `unique_fixture_copy!/1`) should
  not be reimplemented per test file. If a helper appears in two test files,
  it belongs in `test/support/`.

### 1.3 What NOT to DRY

- The `@default_extensions` duplication between `Loader` and `Config` is
  deliberate — `Config` is the source of truth, `Loader` has a fallback
  for when `Config` is not started. Do not "fix" this.

- Error reason atoms are module-scoped (`:lexer`, `:parser`, etc.). They
  should NOT be shared or abstracted — each module owns its own namespace.

---

## 2. Comments: only necessary documentation

### 2.1 Comments to require

- **`@moduledoc`**: every module MUST have one (or `@moduledoc false` for
  private/support modules). The moduledoc is the design doc — it must explain
  *why* the code exists and any deviations from upstream Liquid or from naive
  implementations. Review for: does the moduledoc explain the "why"?

- **`@doc` + `@spec`**: every public function MUST have both. `@doc` should
  include `## Examples` with doctests (`iex>` prompts, 4-space indent) when
  the function is part of the public API or when error shapes are non-obvious.

- **`@impl true`**: required on all callback implementations (GenServer,
  `@behaviour Alembic.Filter`, `defexception message/1`).

- **Section banners**: `# ---- Section name ----` comment dividers for groups
  of private helpers. Review that they exist and are semantically correct.

- **Inline `#` for non-obvious invariants**: comments that explain
  *why something must be a certain way* (e.g., iolist vs `<>`, async cast
  vs sync get, Liquid truthiness vs Elixir truthiness, TOCTOU safety in
  Loader). These are the only acceptable inline comments.

### 2.2 Comments to reject

- **"What" comments**: `# tokenize the input`, `# parse the tokens`,
  `# evaluate the AST` — these restate what the code does. The function
  name already says this. Reject.

- **Redundant spec-restating comments**: `# returns {:ok, result} or
  {:error, reason}` when `@spec` already says exactly that. Reject.

- **TODO/FIXME in production code**: `mix credo` exits with status 2 on
  any TODO. They must be turned into issues, not left in code. Reject.

- **Stale comments**: comments describing behavior that no longer matches
  the code. Reject — fix the comment or remove it.

- **Copyright/license headers in source files**: the LICENSE file is the
  source of truth. Reject.

### 2.3 Comment style

- Use `#` (not `#--`, `#%%`, etc.).
- No trailing whitespace after `#`.
- Section banners use the `# ---- Name ----` pattern, no exceptions.
- Inline comments are separated from code by at least one space.
- Multi-line rationale comments use `#` on every line, not `# """`.

---

## 3. Module and function structure

### 3.1 Module layout (top to bottom)

1. `@moduledoc` (or `@moduledoc false`)
2. `use` / `require` / `alias` (grouped, multi-alias with leading space
   inside braces: `alias Alembic.{AST, Cache, Context}`)
3. `@behaviour` (if applicable)
4. `@type` definitions
5. `@default_*` module attributes
6. Public functions with `@doc` + `@spec`
7. `# ---- Section ----` banners
8. Private `defp` functions

Review that new modules follow this order exactly.

### 3.2 Function conventions

- **Bang variants** for every public error-returning function. If `foo/2`
  returns `{:ok, _} | {:error, _}`, there must be a `foo!/2` that raises
  `Alembic.TemplateError`.

- **`do_` prefix** for private implementation when a public function does
  setup (e.g., `tokenize/1` → `do_tokenize/2`). Review that this pattern
  is followed, not inlined.

- **Predicates end in `?`** (`enabled?/0`, `blank?/1`, `truthy?/1`).
  Review naming.

- **Pattern matching over conditionals**: multi-clause `def`/`defp` with
  pattern matching on binaries, tuples, and guards is preferred over
  `case`/`cond` when dispatching on shape. Review that new functions
  follow this.

- **`with` chains** for sequential dependent steps that must all succeed.
  `case` for happy path with a distinguishable failure. Review usage is
  appropriate.

---

## 4. Error handling

### 4.1 Error shape

Errors MUST be tagged tuples: `{:error, {:module_prefix, reason}}`.

```
{:error, {:lexer, {:unterminated_output, %{line: 1, col: 1}}}}
{:error, {:parser, {:missing_end_tag, "endif", %{line: 1, col: 1}}}}
{:error, {:evaluator, {:undefined_variable, ["name"]}}}
{:error, {:loader, {:template_not_found, paths}}}
```

- The module prefix atom is owned by the module that produces the error.
- Position goes last when present.
- Missing closing tags use the **opening** tag's position (not the current
  position).
- `reason` atoms must be namespaced and descriptive.

Review that new error atoms are unique, namespaced, and documented in
the producing module's `@type reason :: ...`.

### 4.2 `raise` usage

- `raise` for programmer errors only (`Context.pop_scope/1` on root scope).
- `raise Alembic.TemplateError` only via bang-API functions.
- `rescue` only for coercion safety (e.g., `safe_atom`, `coerce_to_string`).
  Review that rescue blocks are narrow and justified.

---

## 5. AST conventions

- **Tagged tuples, NOT structs** for AST nodes. This is deliberate — it
  keeps pattern matching in the evaluator exhaustive (compiler warnings on
  unhandled nodes). Review that no new AST node type is a struct.

- Adding a node type requires updating BOTH `AST`'s `@type` AND every
  `eval_node/2` clause in the evaluator AND the relevant parser clause.
  Review that all three are updated together.

- **Iolist accumulation** with a single `IO.iodata_to_binary/1` at the
  boundary. Never `<>` in a loop — it's O(n²). Review that evaluator
  output uses nested lists, not string concatenation.

- **Whitespace control** is resolved at parse time (`apply_whitespace_control/1`).
  The AST has no `strip_left`/`strip_right` fields. Do not add them.

- **Inheritance is a preprocess pass.** `Inheritance.preprocess/2` runs
  before `Evaluator.eval/2` and splices out `{:block, _, _}` nodes. The
  evaluator has no `:block` clause. Review that no evaluator change
  introduces block handling.

---

## 6. Performance

- **Cache key is `{path, mtime}`.** A modified file is automatically a
  miss. No explicit invalidation needed for source edits.

- **`Cache.get/1` is a direct ETS lookup** (bypasses mailbox).
  `put/2`/`invalidate/1`/`clear/0` are casts through the GenServer.
  Review that read paths don't accidentally go through the GenServer.

- **Logger with zero-arity function**: `Logger.debug(fn -> ... end)` so
  interpolation only runs at configured level. Review that no new logging
  eagerly interpolates.

- **`Enum.reduce_while/3`** is the fold pattern, not `Enum.map/2` when
  state threading or short-circuiting is needed. Review usage.

---

## 7. Testing

### 7.1 Test structure

- Every test file starts with `doctest <Module>`.
- Use private helper functions for repeated setup, not `setup`/`setup_all`
  blocks (this is the established convention).
- `describe` blocks group by feature, not by function arity.
- Test names: lowercase descriptive sentences.

### 7.2 Assertions

- Pattern-match assertions: `assert {:ok, [{:text, "hello"}]} = parse("hello")`
- Pin operator for exact values: `assert {:ok, ^expected}`
- `assert html =~ "<title>"` for substring checks
- Error shape assertions pin the full tagged tuple:
  `assert {:error, {:unterminated_output, %{line: 1, col: 1}}} = Lexer.tokenize("{{ name")`

### 7.3 Cache tests

- Use `unique_fixture_copy!/1` to avoid shared cache state between tests.
- Call `Alembic.Cache.sweep()` after `render_file` to force async `put/2`
  before synchronous `get/1`.
- Clean up with `on_exit/1`.

### 7.4 Integration tests

- Exercise the full pipeline through `Alembic`'s public API only.
- Never call internal modules directly.

### 7.5 Property tests

- Hand-written generators only (`test/support/lexer_generators.ex`).
  No `StreamData` or `:proper` — preserves zero-runtime-deps policy.

### 7.6 What to flag in test review

- Missing `doctest` call at top of file.
- Tests that share cache state (same fixture path across tests).
- `setup`/`setup_all` blocks where a helper function would be cleaner.
- Missing `async: true` on unit tests (integration tests that touch Cache
  should NOT be async).
- Missing `MIX_ENV=test mix compile --warnings-as-errors` awareness —
  test-only modules must not produce warnings.

---

## 8. Zero-runtime-deps policy

Alembic has zero runtime dependencies. This is a hard constraint.

- **Never add a runtime dependency.** Dev/test deps must be marked
  `runtime: false`.
- **No `:telemetry`** — use `Logger.debug(fn -> ... end)` instead.
- **No `StreamData`/`:proper`** in property tests.
- **No JSON libraries** — use `Jason` only if it becomes a dev dep for
  benchmarks (it isn't today).

Review that no new `defp` or module introduces a behaviour/use/import
from an unlisted dependency.

---

## 9. Documentation and compatibility

- **`COMPATIBILITY.md`** is the authoritative matrix for what Alembic
  supports vs. deviates from vs. leaves out of upstream Liquid. Any
  feature change must update this file.

- **`docs/grammar.md`** is the authoritative EBNF grammar. Grammar
  changes must update this file.

- **`CHANGELOG.md`** follows Keep a Changelog. User-facing changes must
  have an entry.

- **Public API moduledocs** should include an ASCII pipeline diagram
  or mermaid diagram when explaining data flow.

---

## 10. CI compliance checklist

For every PR, verify all of these pass before approving:

- [ ] `mix format --check-formatted` — no formatting issues
- [ ] `mix compile --warnings-as-errors` — no compiler warnings (dev)
- [ ] `MIX_ENV=test mix compile --warnings-as-errors` — no warnings (test)
- [ ] `mix test` — all tests pass
- [ ] `mix credo --strict` — no credo issues (including zero TODOs)
- [ ] `mix dialyzer` — no type errors
- [ ] `mix hex.build` — package builds successfully

---

## 11. Review checklist (summary)

For each changed file:

1. **Does the moduledoc explain why?** Not just what — the rationale.
2. **Does every public function have `@doc` + `@spec`?**
3. **Are new AST nodes added to `AST`'s `@type` AND the evaluator?**
4. **Is error handling a properly namespaced tagged tuple?**
5. **Is the new logic DRY with existing helpers?** (check step functions,
   parser helpers, evaluator folds, coercion helpers)
6. **Are comments explaining *why*, not *what*?** Remove redundant comments.
7. **Is output accumulated as iolists, not `<>`?**
8. **Are new tests added with `doctest` at the top?**
9. **Does `COMPATIBILITY.md` or `docs/grammar.md` need updating?**
10. **Are all CI gates green?**

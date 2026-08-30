# Alembic Template Grammar

This document is the formal EBNF grammar for the Alembic template language,
as actually implemented by `Alembic.Lexer` (Milestone 1.2) and
`Alembic.Parser` / `Alembic.Parser.Expression` (Milestone 1.3). It supersedes
the starting-point grammar sketched in issue 1.3.1 — several details were
refined once the Lexer and Expression parser were built; those refinements
and the ambiguities they resolve are called out below.

---

## 1. Full EBNF grammar

```ebnf
(* Top-level *)
template     = { node } ;

node         = text
             | output
             | if_block
             | for_block
             | assign
             | block
             | extends
             | include
             ;

(* Literal text passthrough. Never contains a raw "{{" or "{%" — those always
   open a delimiter. `{% comment %}` and `{% raw %}` blocks are consumed
   entirely by the Lexer and never reach this grammar: a comment block
   produces zero tokens, and a raw block collapses to a single TEXT_TOKEN. *)
text         = TEXT_TOKEN ;

(* Variable output: {{ expr }}. Filters are part of `expr` itself — see the
   expression grammar in section 2 — not a separate trailing repetition, as
   an earlier draft of this grammar suggested (resolved in section 3.1). The
   base of an output expression must be a bare variable path, optionally
   wrapped in a filter chain: literal or comparison bases are rejected by
   the parser with `{:unsupported_output_expression, raw}`. *)
output       = OUTPUT_OPEN , expr , OUTPUT_CLOSE ;

(* If / elsif* / else? / endif *)
if_block     = TAG_OPEN , "if" , expr , TAG_CLOSE
               , template
               , { TAG_OPEN , "elsif" , expr , TAG_CLOSE , template }
               , [ TAG_OPEN , "else" , TAG_CLOSE , template ]
               , TAG_OPEN , "endif" , TAG_CLOSE
               ;

(* For loop: for var in iterable *)
for_block    = TAG_OPEN , "for" , IDENT , "in" , expr , TAG_CLOSE
               , template
               , [ TAG_OPEN , "else" , TAG_CLOSE , template ]
               , TAG_OPEN , "endfor" , TAG_CLOSE
               ;

(* Variable assignment *)
assign       = TAG_OPEN , "assign" , IDENT , "=" , expr , TAG_CLOSE ;

(* Template inheritance *)
extends      = TAG_OPEN , "extends" , STRING , TAG_CLOSE ;
block        = TAG_OPEN , "block" , IDENT , TAG_CLOSE
               , template
               , TAG_OPEN , "endblock" , TAG_CLOSE
               ;

(* Partial inclusion *)
include      = TAG_OPEN , "include" , STRING
               , [ "with" , variable_list ]
               , TAG_CLOSE
               ;

variable_list = assignment_pair , { "," , assignment_pair } ;
assignment_pair = IDENT , ":" , expr ;

(* Terminals produced by the Lexer (Alembic.Token) *)
TEXT_TOKEN   = (* any run of characters not starting a Liquid delimiter *) ;
OUTPUT_OPEN  = "{{" | "{{-" ;
OUTPUT_CLOSE = "}}" | "-}}" ;
TAG_OPEN     = "{%" | "{%-" ;
TAG_CLOSE    = "%}" | "-%}" ;
```

The dash variants of `OUTPUT_OPEN`/`OUTPUT_CLOSE`/`TAG_OPEN`/`TAG_CLOSE` carry
whitespace-strip intent (`strip_left` / `strip_right`) as boolean flags on
the token itself; they do not otherwise change parsing.

---

## 2. Expression grammar

The content inside `{{ ... }}` and after a tag keyword (`if`, `for ... in`,
`assign ... =`) is not tokenized character-by-character by the main grammar
above — the Lexer hands the Parser a single raw string per output/tag token,
and `Alembic.Parser.Expression` parses that string with its own recursive
descent grammar:

```ebnf
expr             = or_expr ;
or_expr          = and_expr , { "or" , and_expr } ;
and_expr         = not_expr , { "and" , not_expr } ;
not_expr         = [ "not" ] , comparison ;
comparison       = filtered_primary , [ compare_op , filtered_primary ] ;
filtered_primary = primary , { filter } ;
primary          = variable | literal ;

variable     = IDENT , { "." , ( IDENT | INTEGER ) | "[" , ( STRING | INTEGER ) , "]" } ;
literal      = STRING | INTEGER | FLOAT | "true" | "false" | "nil" | "null" ;

filter       = "|" , IDENT , [ ":" , expr , { "," , expr } ] ;

compare_op   = "==" | "!=" | ">" | "<" | ">=" | "<=" | "contains" ;

IDENT        = letter , { letter | digit | "_" } ;
STRING       = '"' , { any_char } , '"' | "'" , { any_char } , "'" ;
INTEGER      = [ "-" ] , digit , { digit } ;
FLOAT        = INTEGER , "." , digit , { digit } ;
```

### AST mapping

Each production maps onto exactly one `Alembic.AST.expr()` shape:

| Production | AST node |
|---|---|
| `variable` | `{:variable, path}` — `path :: [String.t()]` |
| `literal` | `{:literal, value}` |
| `filtered_primary` (≥ 1 filter) | `{:filter_chain, base_expr, [filter, ...]}` |
| `comparison` (with `compare_op`) | `{:compare, op, left, right}` |
| `and_expr` / `or_expr` | `{:logical, :and \| :or, left, right}` |
| `not_expr` (with `not`) | `{:not, expr}` |
| `filter` | `{:filter, name, args}` — `args :: [expr()]` |

Top-level node productions map onto `Alembic.AST.ast_node()` shapes:

| Production | AST node |
|---|---|
| `text` | `{:text, content}` |
| `output` | `{:output, path, filters}` — see the output-base restriction below |
| `if_block` | `{:if, condition, then_branch, elsif_branches, else_branch}` |
| `for_block` | `{:for, var, iterable, body, else_branch}` |
| `assign` | `{:assign, var, expr}` |
| `extends` | `{:extends, template_name}` |
| `block` | `{:block, name, body}` |
| `include` | `{:include, template_name, variables}` |

---

## 3. LL(1) analysis

### FIRST sets

| Rule | FIRST set |
|---|---|
| `node` | `TEXT_TOKEN`, `OUTPUT_OPEN`, `TAG_OPEN` |
| `output` | `OUTPUT_OPEN` |
| `if_block` / `for_block` / `assign` / `extends` / `block` / `include` | `TAG_OPEN` (disambiguated by the keyword immediately inside — see below) |
| `or_expr` → `and_expr` → `not_expr` → `comparison` → `filtered_primary` → `primary` | `IDENT`, `STRING`, `INTEGER`, `FLOAT`, `"true"`, `"false"`, `"nil"`, `"null"`, `"-"` (negative number), `"not"` |

`node`'s three alternatives (`text`, `output`, tag-family) have disjoint
FIRST sets at the token-type level: the Lexer already resolved
text-vs-delimiter, so the Parser's dispatch on `{:text, _}` vs `{:output,
_, _, _}` vs `{:tag, _, _, _}` is a single-token lookahead — LL(1) holds
trivially at this level.

### Lookahead beyond 1 token: the tag keyword

All seven tag-family productions (`if_block`, `for_block`, `assign`,
`extends`, `block`, `include`, plus their `end*`/`elsif`/`else` continuation
tags) share the same `TAG_OPEN` terminal. The Lexer does not split the tag
keyword out as a separate terminal — it hands the Parser one raw string
(e.g. `"if user.admin"`). The Parser resolves this by pattern-matching the
**string prefix** of that raw content (`"if " <> condition`, `"for " <>
rest`, `"assign " <> rest`, etc.) before dispatching, which is equivalent to
one token of *lexical* lookahead beyond the `TAG_OPEN` terminal but does not
require backtracking — it is a deterministic string-prefix dispatch, still
O(1) per tag.

### Right-recursion, not left-recursion

`or_expr`, `and_expr`, and the `{ elsif ... }` / for-loop `template`
sequences are all written with **right recursion** in the grammar above
(`X = Y , { op , Y }`, i.e. a repetition, not `X = X , op , Y`). A textbook
left-recursive grammar (`or_expr = or_expr , "or" , and_expr | and_expr`)
would blow the Elixir call stack in a naive recursive descent implementation
before ever returning. `Alembic.Parser.Expression` implements the repetition
as an explicit accumulating loop (`parse_or_rest/2`, `parse_and_rest/2`)
that folds left, producing a left-associative tree without recursing on the
left operand — see section 4.

---

## 4. Worked parse tree example

Template:

```liquid
{% for post in site.posts %}
  <h2>{{ post.title | upcase }}</h2>
  {% if post.featured %}★{% endif %}
{% endfor %}
```

### Concrete syntax tree (all tokens, including delimiters)

```
template
└─ tag_open "{%" tag_content "for post in site.posts" tag_close "%}"
   ├─ text "\n  <h2>"
   ├─ output_open "{{" expr "post.title | upcase" output_close "}}"
   ├─ text "</h2>\n  "
   ├─ tag_open "{%" tag_content "if post.featured" tag_close "%}"
   │  └─ text "★"
   ├─ tag_open "{%" tag_content "endif" tag_close "%}"
   ├─ text "\n"
   └─ tag_open "{%" tag_content "endfor" tag_close "%}"
```

### Abstract syntax tree (semantic nodes only)

```
[
  {:for, "post", {:variable, ["site", "posts"]},
    [
      {:text, "\n  <h2>"},
      {:output, ["post", "title"], [{:filter, "upcase", []}]},
      {:text, "</h2>\n  "},
      {:if, {:variable, ["post", "featured"]},
        [{:text, "★"}],
        [],
        nil},
      {:text, "\n"}
    ],
    nil}
]
```

Note how the CST retains every delimiter and the literal tag-content string,
while the AST discards punctuation and keeps only the resolved `path()`,
`expr()`, and node structure — the classic CST-vs-AST distinction from
compiler theory.

---

## 5. Known ambiguities and their resolution

### 5.1 `{% else %}` is valid inside both `if_block` and `for_block`

The grammar alone cannot distinguish `TAG_OPEN , "else" , TAG_CLOSE` inside
an `if_block` from the same production inside a `for_block` — both simply
see the literal string `"else"`. `Alembic.Parser` resolves this via **call
stack context**: `parse_if_body/2` and `parse_for_body/2` each independently
recognize `"else"` as *their own* stopping token and hand control back to
their caller; the grammar production being parsed is implicit in which
parser function is currently on the call stack, not encoded in the token
stream itself. This is standard practice for recursive descent — the parse
state lives in which functions are active, not in a separate explicit stack.

### 5.2 Filter binding: primary-level, not output-level

The starting-point grammar in issue 1.3.1 placed `{ filter }` outside
`expr` entirely, at the `output` production (`output = OUTPUT_OPEN, expr, {
filter }, OUTPUT_CLOSE`). That would make filters inexpressible inside
`{% if %}` / `{% for %}` conditions, and would not match
`Alembic.Parser.Expression`'s own public contract (`Expression.parse("n |
upcase")` — no output tag involved at all, filters as part of the
expression). Resolved by binding `{ filter }` at `filtered_primary` —
tighter than comparison and logical operators — so `x | size > 0` parses
as `{:compare, :gt, {:filter_chain, {:variable, ["x"]}, [{:filter, "size",
[]}]}, {:literal, 0}}`, and `name | upcase` parses standalone as a
`{:filter_chain, ...}` node with no comparison wrapper.

Consecutive filters attach to a **single** `{:filter_chain, base, filters}`
node carrying a list of all filters, in source order — `a | f | g` is
`{:filter_chain, a_expr, [{:filter, "f", []}, {:filter, "g", []}]}`, not
`{:filter_chain, {:filter_chain, a_expr, [f]}, [g]}`. This matches
`Alembic.AST.filter_chain`'s type (`{:filter_chain, expr(), [filter()]}` —
one list, not nested wrappers) and is why the filter chain is
**right-associative in evaluation order but flat in representation**: each
filter is applied in list order to the previous filter's output.

### 5.3 `contains` is a binary operator, not a function call

`s contains "hello"` looks superficially like it could be a function-call
form (`contains(s, "hello")`), but the grammar treats `contains` exactly
like `>` or `==`: an infix `compare_op` between two `filtered_primary`
operands (`comparison = filtered_primary, [compare_op, filtered_primary]`).
The Lexer's own tokenizer never sees `contains` as special — it is scanned
as a plain `IDENT` and only reclassified as `{:op, :contains}` by
`Alembic.Parser.Expression`'s tokenizer, alongside the true keywords `and`,
`or`, `not`, `true`, `false`, `nil`, `null`. There is no parenthesized
call syntax anywhere in this grammar.

### 5.4 `not`/`and`/`or` precedence — correcting the illustrative example

Issue 1.3.1's task list states operator precedence as `not > and > or`
(`not` binds tightest, `or` loosest) and separately claims `not a and b or
c` parses as `(not a) and (b or c)`. **These two statements are mutually
inconsistent.** Under `not > and > or`, `or` is the *lowest*-precedence
operator, so it must be the outermost/last-applied split — meaning `or`'s
two operands are `not a and b` and `c`, giving `((not a) and b) or c`, not
`(not a) and (b or c)` (which would require `and` to bind loosest, the
opposite of the stated rule).

`Alembic.Parser.Expression` implements the grammar as written above
(`or_expr = and_expr, {"or", and_expr}`, `and_expr = not_expr, {"and",
not_expr}`, `not_expr = ["not"], comparison`), which is the correct
encoding of `not > and > or`, and produces `((not a) and b) or c`. This is
verified directly in `test/alembic/expression_test.exs`. The illustrative
example in issue 1.3.1 is treated as erroneous and superseded by this
document.

### 5.5 Context-sensitive constraint: `extends` must be first

Per issue 1.1.2's Academic Note, this grammar is **not** strictly
context-free in the Chomsky-hierarchy sense: `extends` may appear **at most
once**, and only as the **first** node of a `template`. The EBNF for
`template = { node }` alone cannot express "at most one, and only first" —
that would require a more complex production (e.g. `template = [ extends ] ,
{ node - extends }`, which EBNF supports but which obscures that `extends`
is otherwise a completely ordinary `node`). `Alembic.Parser` enforces this
constraint procedurally instead: `parse_template/1` checks node position
directly and returns `{:error, :extends_not_first}` if an `extends` node is
produced anywhere but the head of the list. This is a textbook example of a
**context-sensitive** rule enforced during parsing/semantic analysis rather
than encoded in the context-free grammar itself.

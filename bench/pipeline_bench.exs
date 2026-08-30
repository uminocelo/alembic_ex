source = File.read!(Path.join(__DIR__, "fixtures/pipeline_template.liquid"))
{:ok, tokens} = Alembic.Lexer.tokenize(source)
{:ok, ast} = Alembic.Parser.parse(tokens)

assigns = %{
  "site" => %{"title" => "Bench"},
  "user" => %{"active" => true, "name" => "Alice"},
  "total" => 150,
  "status" => "inactive",
  "tags" => ["a", "b", "c"],
  "post" => %{
    "title" => String.duplicate("x", 60),
    "author" => %{"name" => "Bob"},
    "date" => "2024-01-01"
  }
}

# The fixture has 5 {% include %} tags — a loader must be wired up (both
# here, for eval_only, and via `opts` below, for render_string/3 and
# render/3) or those includes fail to resolve.
opts = [roots: [Path.join(__DIR__, "fixtures")]]
ctx = Alembic.Context.new(assigns) |> Alembic.Context.loader(Alembic.Loader.build_loader(opts))

Benchee.run(
  %{
    "lexer_only" => fn -> Alembic.Lexer.tokenize(source) end,
    "parser_only" => fn -> Alembic.Parser.parse(tokens) end,
    "eval_only" => fn -> Alembic.Evaluator.eval(ast, ctx) end,
    "full_cold (render_string/3)" => fn -> Alembic.render_string(source, assigns, opts) end,
    "full_precompiled (render/3)" => fn -> Alembic.render(ast, assigns, opts) end
  },
  time: 5,
  memory_time: 2,
  warmup: 2
)

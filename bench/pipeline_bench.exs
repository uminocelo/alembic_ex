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

ctx = Alembic.Context.new(assigns)

Benchee.run(
  %{
    "lexer_only" => fn -> Alembic.Lexer.tokenize(source) end,
    "parser_only" => fn -> Alembic.Parser.parse(tokens) end,
    "eval_only" => fn -> Alembic.Evaluator.eval(ast, ctx) end,
    "full_cold (render_string/3)" => fn -> Alembic.render_string(source, assigns) end,
    "full_precompiled (render/3)" => fn -> Alembic.render(ast, assigns) end
  },
  time: 5,
  memory_time: 2,
  warmup: 2
)

template = File.read!(Path.join(__DIR__, "fixtures/large_template.liquid"))

Benchee.run(
  %{
    "tokenize/1 (50 KB fixture)" => fn -> Alembic.Lexer.tokenize(template) end
  },
  time: 5,
  memory_time: 2,
  warmup: 2
)

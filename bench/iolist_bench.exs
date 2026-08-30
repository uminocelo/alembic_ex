# Naive string-concatenation evaluator, for comparison only — NOT
# production code. Handles only text/output nodes against a flat map
# context, enough to demonstrate the O(n^2) cost of repeated `<>`
# concatenation against Alembic.Evaluator's real O(n) iolist accumulation.
defmodule Alembic.Bench.NaiveConcatEvaluator do
  def eval(nodes, assigns) do
    Enum.reduce(nodes, "", fn
      {:text, content}, acc -> acc <> content
      {:output, [key], []}, acc -> acc <> to_string(Map.get(assigns, key, ""))
    end)
  end
end

build_ast = fn size ->
  Enum.flat_map(1..size, fn i ->
    [{:text, "item-#{i}: "}, {:output, ["value"], []}, {:text, "\n"}]
  end)
end

assigns = %{"value" => "hello world"}
ctx = Alembic.Context.new(assigns)

sizes = %{
  "small (~10 output nodes)" => 10,
  "medium (~100 output nodes)" => 100,
  "large (~1000 output nodes)" => 1000,
  "very large (~50,000 output nodes)" => 50_000
}

Enum.each(sizes, fn {label, size} ->
  ast = build_ast.(size)

  IO.puts("\n=== #{label} ===")

  Benchee.run(
    %{
      "iolist (Alembic.Evaluator)" => fn -> Alembic.Evaluator.eval(ast, ctx) end,
      "naive string concat" => fn -> Alembic.Bench.NaiveConcatEvaluator.eval(ast, assigns) end
    },
    time: 3,
    memory_time: 1,
    warmup: 1
  )
end)

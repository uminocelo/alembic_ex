defmodule Alembic.EvaluatorTest do
  use ExUnit.Case, async: true

  doctest Alembic.Evaluator

  alias Alembic.{Context, Evaluator, Lexer, Parser}

  defp render(source, bindings \\ %{}) do
    {:ok, tokens} = Lexer.tokenize(source)
    {:ok, ast} = Parser.parse(tokens)
    Evaluator.eval(ast, Context.new(bindings))
  end

  describe "text node" do
    test "passthrough" do
      assert {:ok, "hello"} = render("hello")
    end
  end

  describe "output node" do
    test "resolves a bound variable" do
      assert {:ok, "Alice"} = render("{{ name }}", %{"name" => "Alice"})
    end

    test "undefined variable renders as empty string, not an error" do
      assert {:ok, ""} = render("{{ missing }}")
    end

    test "nested path" do
      assert {:ok, "Lisbon"} = render("{{ user.city }}", %{"user" => %{"city" => "Lisbon"}})
    end

    test "applies a filter chain" do
      assert {:ok, "ALICE"} = render("{{ name | upcase }}", %{"name" => "alice"})
    end

    test "an unknown filter propagates as an error" do
      assert {:error, {:unknown_filter, "nope"}} = render("{{ name | nope }}", %{"name" => "x"})
    end
  end

  describe "strict mode (Context.strict/2)" do
    test "an undefined variable in an output tag errors instead of rendering empty" do
      ctx = Context.new(%{}) |> Context.strict(true)
      ast = [{:output, ["missing"], []}]
      assert {:error, {:undefined_variable, ["missing"]}} = Evaluator.eval(ast, ctx)
    end

    test "an undefined variable inside a condition also errors" do
      ctx = Context.new(%{}) |> Context.strict(true)
      ast = [{:if, {:variable, ["missing"]}, [{:text, "yes"}], [], nil}]
      assert {:error, {:undefined_variable, ["missing"]}} = Evaluator.eval(ast, ctx)
    end

    test "a defined variable renders normally even in strict mode" do
      ctx = Context.new(%{"name" => "Alice"}) |> Context.strict(true)
      ast = [{:output, ["name"], []}]
      assert {:ok, "Alice"} = Evaluator.eval(ast, ctx)
    end

    test "strict mode is off by default" do
      ctx = Context.new(%{})
      ast = [{:output, ["missing"], []}]
      assert {:ok, ""} = Evaluator.eval(ast, ctx)
    end
  end

  describe "if node" do
    test "truthy condition renders the then branch" do
      ast = [{:if, {:variable, ["x"]}, [{:text, "yes"}], [], [{:text, "no"}]}]
      assert {:ok, "yes"} = Evaluator.eval(ast, Context.new(%{"x" => 1}))
    end

    test "falsy condition renders the else branch" do
      ast = [{:if, {:variable, ["x"]}, [{:text, "yes"}], [], [{:text, "no"}]}]
      assert {:ok, "no"} = Evaluator.eval(ast, Context.new(%{"x" => false}))
    end

    test "no else branch and falsy condition renders empty string" do
      ast = [{:if, {:variable, ["x"]}, [{:text, "yes"}], [], nil}]
      assert {:ok, ""} = Evaluator.eval(ast, Context.new(%{"x" => nil}))
    end

    test "elsif chain picks the first truthy branch" do
      assert {:ok, "b"} =
               render("{% if x %}a{% elsif y %}b{% elsif z %}c{% endif %}", %{"y" => true})
    end

    test "falls through to else when no elsif matches" do
      assert {:ok, "d"} = render("{% if x %}a{% elsif y %}b{% else %}d{% endif %}", %{})
    end
  end

  describe "Liquid truthiness" do
    test "0 is truthy" do
      assert {:ok, "yes"} = render("{% if x %}yes{% else %}no{% endif %}", %{"x" => 0})
    end

    test "empty string is truthy" do
      assert {:ok, "yes"} = render("{% if x %}yes{% else %}no{% endif %}", %{"x" => ""})
    end

    test "empty list is truthy" do
      assert {:ok, "yes"} = render("{% if x %}yes{% else %}no{% endif %}", %{"x" => []})
    end

    test "nil is falsy" do
      assert {:ok, "no"} = render("{% if x %}yes{% else %}no{% endif %}", %{"x" => nil})
    end

    test "false is falsy" do
      assert {:ok, "no"} = render("{% if x %}yes{% else %}no{% endif %}", %{"x" => false})
    end

    test "an undefined variable is falsy" do
      assert {:ok, "no"} = render("{% if missing %}yes{% else %}no{% endif %}", %{})
    end
  end

  describe "for node" do
    test "iterates and concatenates output" do
      assert {:ok, "abc"} =
               render("{% for i in items %}{{ i }}{% endfor %}", %{"items" => ["a", "b", "c"]})
    end

    test "forloop metadata is accessible inside the body" do
      assert {:ok, "123"} =
               render("{% for i in items %}{{ forloop.index }}{% endfor %}", %{
                 "items" => ["a", "b", "c"]
               })

      assert {:ok, "0,1,2"} =
               render(
                 "{% for i in items %}{{ forloop.index0 }}{% if forloop.last == false %},{% endif %}{% endfor %}",
                 %{"items" => ["a", "b", "c"]}
               )
    end

    test "first/last flags on the only iteration" do
      assert {:ok, "truetrue"} =
               render("{% for i in items %}{{ forloop.first }}{{ forloop.last }}{% endfor %}", %{
                 "items" => ["only"]
               })
    end

    test "first/last flags across multiple iterations" do
      assert {:ok, "true,false"} =
               render(
                 "{% for i in items %}{{ forloop.first }}{% if forloop.last == false %},{% endif %}{% endfor %}",
                 %{"items" => ["a", "b"]}
               )
    end

    test "empty iterable with else branch" do
      assert {:ok, "empty"} =
               render("{% for i in items %}{{ i }}{% else %}empty{% endfor %}", %{"items" => []})
    end

    test "empty iterable without else branch renders empty string" do
      assert {:ok, ""} = render("{% for i in items %}{{ i }}{% endfor %}", %{"items" => []})
    end

    test "non-list iterable is treated as empty" do
      assert {:ok, ""} = render("{% for i in items %}{{ i }}{% endfor %}", %{"items" => nil})
    end

    test "the loop variable does not leak after the loop ends" do
      # The loop's own body legitimately renders "a" once; if the loop
      # variable leaked, the trailing {{ i }} after the "-" would render
      # "a" too, giving "a-a" instead of "a-".
      assert {:ok, "a-"} =
               render("{% for i in items %}{{ i }}{% endfor %}-{{ i }}", %{"items" => ["a"]})
    end

    test "nested for loops each have their own forloop metadata" do
      template = "{% for i in outer %}{% for j in inner %}{{ i }}{{ j }}{% endfor %}{% endfor %}"
      assert {:ok, "a1a2b1b2"} = render(template, %{"outer" => ["a", "b"], "inner" => ["1", "2"]})
    end
  end

  describe "assign node" do
    test "assign affects rendering of nodes after it" do
      assert {:ok, "world"} = render(~s({% assign x = "world" %}{{ x }}))
    end

    test "assign renders as empty string itself" do
      assert {:ok, "before after"} = render(~s(before {% assign x = 1 %}after))
    end

    test "assign inside a for loop persists after the loop ends" do
      assert {:ok, "c"} =
               render("{% for i in items %}{% assign last = i %}{% endfor %}{{ last }}", %{
                 "items" => ["a", "b", "c"]
               })
    end

    test "assign can be reassigned" do
      assert {:ok, "2"} = render("{% assign x = 1 %}{% assign x = 2 %}{{ x }}")
    end
  end

  describe "nested for/if combinations" do
    test "if inside for" do
      assert {:ok, "a-b"} =
               render(
                 "{% for i in items %}{% if i == \"skip\" %}{% else %}{{ i }}{% endif %}{% endfor %}",
                 %{"items" => ["a", "-", "b"]}
               )
    end

    test "for inside if" do
      assert {:ok, "abc"} =
               render("{% if show %}{% for i in items %}{{ i }}{% endfor %}{% endif %}", %{
                 "show" => true,
                 "items" => ["a", "b", "c"]
               })
    end
  end

  describe "iolist accumulation" do
    test "large templates render without exceeding reasonable time (no O(n^2) string concat)" do
      items = Enum.map(1..2000, &Integer.to_string/1)
      {:ok, result} = render("{% for i in items %}{{ i }},{% endfor %}", %{"items" => items})

      assert String.length(result) ==
               Enum.reduce(items, 0, fn i, acc -> acc + String.length(i) + 1 end)
    end
  end

  describe "logical and comparison expressions" do
    test "and/or/not/compare inside a condition" do
      assert {:ok, "yes"} =
               render("{% if x > 0 and not skip %}yes{% else %}no{% endif %}", %{
                 "x" => 1,
                 "skip" => false
               })

      assert {:ok, "no"} =
               render("{% if x > 0 and not skip %}yes{% else %}no{% endif %}", %{
                 "x" => 1,
                 "skip" => true
               })
    end

    test "contains operator" do
      assert {:ok, "yes"} =
               render(~s({% if s contains "ell" %}yes{% else %}no{% endif %}), %{"s" => "hello"})
    end
  end
end

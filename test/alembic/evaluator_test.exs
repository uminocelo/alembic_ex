defmodule Alembic.EvaluatorTest do
  use ExUnit.Case, async: true

  doctest Alembic.Evaluator

  alias Alembic.{Context, Evaluator, Lexer, Parser}

  defp render(source, bindings \\ %{}) do
    {:ok, tokens} = Lexer.tokenize(source)
    {:ok, ast} = Parser.parse(tokens)
    Evaluator.eval(ast, Context.new(bindings))
  end

  defp condition(cond_source, bindings) do
    render("{% if " <> cond_source <> " %}yes{% else %}no{% endif %}", bindings)
  end

  defp render_strict(source, bindings) do
    {:ok, tokens} = Lexer.tokenize(source)
    {:ok, ast} = Parser.parse(tokens)
    Evaluator.eval(ast, Context.new(bindings) |> Context.strict(true))
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

  describe "dynamic bracket access" do
    test "map key via a variable" do
      assert {:ok, "Lisbon"} =
               render("{{ user[key] }}", %{"user" => %{"city" => "Lisbon"}, "key" => "city"})
    end

    test "list index via an integer variable" do
      assert {:ok, "b"} = render("{{ items[i] }}", %{"items" => ["a", "b", "c"], "i" => 1})
    end

    test "list index via forloop.index0" do
      template = "{% for x in items %}{{ items[forloop.index0] }}{% endfor %}"
      assert {:ok, "abc"} = render(template, %{"items" => ["a", "b", "c"]})
    end

    test "nested dynamic segment" do
      assert {:ok, "Lisbon"} =
               render("{{ data[which.key] }}", %{
                 "data" => %{"city" => "Lisbon"},
                 "which" => %{"key" => "city"}
               })
    end

    test "dynamic segment combined with a static trailing segment" do
      assert {:ok, "Lisbon"} =
               render("{{ users[i].city }}", %{
                 "users" => [%{"city" => "Lisbon"}],
                 "i" => 0
               })
    end

    test "a boolean dynamic segment is a render error" do
      assert {:error, {:invalid_dynamic_segment, true}} =
               render("{{ items[flag] }}", %{"items" => ["a"], "flag" => true})
    end

    test "a nil dynamic segment is a render error" do
      assert {:error, {:invalid_dynamic_segment, nil}} =
               render("{{ items[missing] }}", %{"items" => ["a"]})
    end

    test "strict mode reports the fully resolved dynamic path" do
      assert {:error, {:undefined_variable, ["user", "nope"]}} =
               render_strict("{{ user[key] }}", %{"user" => %{}, "key" => "nope"})
    end

    test "strict mode reports a resolved integer segment as an integer" do
      assert {:error, {:undefined_variable, ["items", 5]}} =
               render_strict("{{ items[i] }}", %{"items" => [], "i" => 5})
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

  describe "break and continue" do
    test "break stops the loop, emitting only preceding output" do
      assert {:ok, "ab"} =
               render(
                 "{% for i in items %}{{ i }}{% if i == \"b\" %}{% break %}{% endif %}{% endfor %}",
                 %{"items" => ["a", "b", "c"]}
               )
    end

    test "continue skips the rest of the current iteration" do
      assert {:ok, "ac"} =
               render(
                 "{% for i in items %}{% if i == \"b\" %}{% continue %}{% endif %}{{ i }}{% endfor %}",
                 %{"items" => ["a", "b", "c"]}
               )
    end

    test "break in a nested loop exits only the innermost loop" do
      template = """
      {% for o in outer %}{% for i in inner %}{% if i == 2 %}{% break %}{% endif %}{{ o }}{{ i }}{% endfor %}{% endfor %}\
      """

      assert {:ok, "a1b1c1"} = render(template, %{"outer" => ["a", "b", "c"], "inner" => [1, 2, 3]})
    end

    test "continue in a nested loop skips only the innermost iteration" do
      template = """
      {% for o in outer %}{% for i in inner %}{% if i == 2 %}{% continue %}{% endif %}{{ o }}{{ i }}{% endfor %}{% endfor %}\
      """

      assert {:ok, "a1a3b1b3c1c3"} =
               render(template, %{"outer" => ["a", "b", "c"], "inner" => [1, 2, 3]})
    end

    test "break does not trigger the else branch" do
      template = "{% for i in items %}{% break %}{% else %}else{% endfor %}"
      assert {:ok, ""} = render(template, %{"items" => ["a", "b"]})
    end

    test "continue does not trigger the else branch" do
      template = "{% for i in items %}{% continue %}{% else %}else{% endfor %}"
      assert {:ok, ""} = render(template, %{"items" => ["a", "b"]})
    end

    test "forloop metadata reflects the iteration at break time" do
      template =
        "{% for i in items %}{% if i == \"b\" %}{% break %}{% endif %}{{ forloop.index }}{% endfor %}"

      assert {:ok, "1"} = render(template, %{"items" => ["a", "b", "c"]})
    end

    test "forloop metadata reflects the iteration at continue time" do
      template =
        "{% for i in items %}{% if i == \"b\" %}{% continue %}{% endif %}{{ forloop.index }}{% endfor %}"

      assert {:ok, "13"} = render(template, %{"items" => ["a", "b", "c"]})
    end

    test "break inside an if inside a for propagates correctly" do
      assert {:ok, "a"} =
               render(
                 "{% for i in items %}{% if i == \"b\" %}{% break %}{% endif %}{{ i }}{% endfor %}",
                 %{"items" => ["a", "b", "c"]}
               )
    end
  end

  describe "cycle" do
    test "advances through values on consecutive calls" do
      assert {:ok, "abab"} =
               render(
                 ~s({% cycle "a", "b" %}{% cycle "a", "b" %}{% cycle "a", "b" %}{% cycle "a", "b" %})
               )
    end

    test "wraps after exhausting values" do
      assert {:ok, "abcab"} =
               render(
                 ~s({% cycle "a", "b", "c" %}{% cycle "a", "b", "c" %}{% cycle "a", "b", "c" %}{% cycle "a", "b", "c" %}{% cycle "a", "b", "c" %})
               )
    end

    test "named groups share state across calls" do
      template = ~s({% cycle "g": "x", "y" %}{% cycle "g": "x", "y" %})
      assert {:ok, "xy"} = render(template)
    end

    test "distinct named groups are independent" do
      template = ~s({% cycle "g1": "a", "b" %}{% cycle "g2": "c", "d" %}{% cycle "g1": "a", "b" %})
      assert {:ok, "acb"} = render(template)
    end

    test "unnamed cycles with same args share state" do
      template = ~s({% cycle "a", "b" %}{% cycle "a", "b" %})
      assert {:ok, "ab"} = render(template)
    end

    test "unnamed cycles with different args are independent" do
      template = ~s({% cycle "a", "b" %}{% cycle "c", "d" %}{% cycle "a", "b" %})
      assert {:ok, "acb"} = render(template)
    end

    test "cycle inside a for loop advances across iterations" do
      template = "{% for i in items %}{% cycle \"odd\", \"even\" %}{% endfor %}"

      assert {:ok, "oddevenoddevenodd"} =
               render(template, %{"items" => [1, 2, 3, 4, 5]})
    end

    test "named cycle inside a for loop shares state across iterations" do
      template = "{% for i in items %}{% cycle \"row\": \"a\", \"b\" %}{% endfor %}"

      assert {:ok, "ababa"} =
               render(template, %{"items" => [1, 2, 3, 4, 5]})
    end

    test "cycle with variable values" do
      assert {:ok, "12"} =
               render("{% cycle x, y %}{% cycle x, y %}", %{"x" => 1, "y" => 2})
    end

    test "separate render calls do not share cycle state" do
      {:ok, result1} = render(~s({% cycle "a", "b" %}))
      {:ok, result2} = render(~s({% cycle "a", "b" %}))
      assert result1 == "a" and result2 == "a"
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

  describe "empty and blank keywords" do
    test "`empty` truth table" do
      assert {:ok, "yes"} = condition("x == empty", %{"x" => ""})
      assert {:ok, "yes"} = condition("x == empty", %{"x" => []})
      assert {:ok, "yes"} = condition("x == empty", %{"x" => %{}})

      assert {:ok, "no"} = condition("x == empty", %{"x" => nil})
      assert {:ok, "no"} = condition("x == empty", %{"x" => false})
      assert {:ok, "no"} = condition("x == empty", %{"x" => " "})
      assert {:ok, "no"} = condition("x == empty", %{"x" => 0})
      assert {:ok, "no"} = condition("x == empty", %{"x" => "x"})
      assert {:ok, "no"} = condition("x == empty", %{"x" => [1]})
    end

    test "`blank` truth table" do
      assert {:ok, "yes"} = condition("x == blank", %{"x" => nil})
      assert {:ok, "yes"} = condition("x == blank", %{"x" => false})
      assert {:ok, "yes"} = condition("x == blank", %{"x" => ""})
      assert {:ok, "yes"} = condition("x == blank", %{"x" => "   "})
      assert {:ok, "yes"} = condition("x == blank", %{"x" => []})
      assert {:ok, "yes"} = condition("x == blank", %{"x" => %{}})

      assert {:ok, "no"} = condition("x == blank", %{"x" => 0})
      assert {:ok, "no"} = condition("x == blank", %{"x" => "x"})
      assert {:ok, "no"} = condition("x == blank", %{"x" => [1]})
    end

    test "`!=` negates the keyword match" do
      assert {:ok, "yes"} = condition("x != empty", %{"x" => nil})
      assert {:ok, "no"} = condition("x != empty", %{"x" => ""})
      assert {:ok, "yes"} = condition("x != blank", %{"x" => "x"})
      assert {:ok, "no"} = condition("x != blank", %{"x" => nil})
    end

    test "reversed operand order is symmetric" do
      assert {:ok, "yes"} = condition("empty == x", %{"x" => ""})
      assert {:ok, "no"} = condition("empty == x", %{"x" => nil})
      assert {:ok, "yes"} = condition("blank == x", %{"x" => nil})
      assert {:ok, "no"} = condition("blank != x", %{"x" => nil})
    end

    test "keywords work with logical operators" do
      assert {:ok, "yes"} =
               condition("x == empty and y == blank", %{"x" => "", "y" => nil})
    end

    test "a keyword with an ordering operator is a render error" do
      assert {:error, {:keyword_requires_equality, :gt, :empty}} =
               condition("x > empty", %{"x" => ""})

      assert {:error, {:keyword_requires_equality, :lt, :blank}} =
               condition("x < blank", %{"x" => ""})
    end

    test "a keyword with contains is a render error" do
      assert {:error, {:keyword_requires_equality, :contains, :empty}} =
               render(~s({% if x contains empty %}yes{% endif %}), %{"x" => "hi"})
    end

    test "a variable named empty still resolves as a variable" do
      assert {:ok, "hi"} = render("{{ empty }}", %{"empty" => "hi"})

      assert {:ok, "hi"} =
               render("{% assign empty = 'hi' %}{{ empty }}", %{})
    end

    test "`{% when empty %}` matches empty subjects" do
      template = "{% case x %}{% when empty %}empty{% else %}other{% endcase %}"
      assert {:ok, "empty"} = render(template, %{"x" => ""})
      assert {:ok, "other"} = render(template, %{"x" => "full"})
      assert {:ok, "other"} = render(template, %{"x" => nil})
    end
  end

  describe "capture node" do
    test "captures rendered body and outputs it later" do
      template = "{% capture x %}Hi {{ name }}{% endcapture %}[{{ x }}]"
      assert {:ok, "[Hi Al]"} = render(template, %{"name" => "Al"})
    end

    test "capture itself renders nothing" do
      assert {:ok, "before after"} =
               render("before {% capture x %}ignored{% endcapture %}after", %{})
    end

    test "nested captures work" do
      template =
        "{% capture x %}outer {% capture y %}inner{% endcapture %}mid{% endcapture %}{{ x }}|{{ y }}"

      assert {:ok, "outer mid|inner"} = render(template, %{})
    end

    test "capture inside a loop re-assigns; final value is the last iteration" do
      template =
        "{% for i in items %}{% capture last %}{{ i }}{% endcapture %}{% endfor %}{{ last }}"

      assert {:ok, "3"} = render(template, %{"items" => [1, 2, 3]})
    end

    test "filters apply to a captured variable" do
      template = "{% capture x %}hi{% endcapture %}{{ x | upcase }}"
      assert {:ok, "HI"} = render(template, %{})
    end

    test "captured variable is visible inside a later include" do
      ctx =
        Alembic.Context.new(%{"name" => "Al"})
        |> Alembic.Context.loader(fn
          "partial" -> {:ok, "[{{ greeting }}]"}
          _ -> {:error, :not_found}
        end)

      ast = [
        {:capture, "greeting", [{:text, "Hi "}, {:output, ["name"], []}]},
        {:include, "partial", %{}}
      ]

      assert {:ok, "[Hi Al]"} = Alembic.Evaluator.eval(ast, ctx)
    end
  end

  describe "unless node (desugared if)" do
    test "renders body when the condition is falsy" do
      assert {:ok, "no"} = render("{% unless x %}no{% endunless %}", %{})
    end

    test "renders the else branch when the condition is truthy" do
      assert {:ok, "yes"} = render("{% unless x %}no{% else %}yes{% endunless %}", %{"x" => true})
    end

    test "0 is truthy, so the unless body over 0 does not render" do
      assert {:ok, "yes"} = render("{% unless n %}no{% else %}yes{% endunless %}", %{"n" => 0})
    end
  end

  describe "case node" do
    test "single-value when matches" do
      template = "{% case x %}{% when 1 %}one{% when 2 %}two{% endcase %}"
      assert {:ok, "two"} = render(template, %{"x" => 2})
    end

    test "multi-value when matches any of its values" do
      template = "{% case x %}{% when 1, 2, 3 %}low{% else %}high{% endcase %}"
      assert {:ok, "low"} = render(template, %{"x" => 3})
      assert {:ok, "high"} = render(template, %{"x" => 9})
    end

    test "else branch on no match" do
      template = "{% case x %}{% when 1 %}one{% else %}other{% endcase %}"
      assert {:ok, "other"} = render(template, %{"x" => 5})
    end

    test "no match and no else renders empty" do
      template = "{% case x %}{% when 1 %}one{% endcase %}"
      assert {:ok, ""} = render(template, %{"x" => 5})
    end

    test "string subjects and values" do
      template = ~s({% case color %}{% when "red" %}R{% when "blue" %}B{% endcase %})
      assert {:ok, "B"} = render(template, %{"color" => "blue"})
    end

    test "variable values in a when" do
      template = "{% case x %}{% when a %}match{% else %}no{% endcase %}"
      assert {:ok, "match"} = render(template, %{"x" => 7, "a" => 7})
    end

    test "first matching when wins" do
      template = "{% case x %}{% when 1 %}first{% when 1 %}second{% endcase %}"
      assert {:ok, "first"} = render(template, %{"x" => 1})
    end

    test "nested case inside for and if" do
      template =
        "{% for i in items %}{% case i %}{% when 1 %}a{% else %}{% if i > 1 %}b{% endif %}{% endcase %}{% endfor %}"

      assert {:ok, "abb"} = render(template, %{"items" => [1, 2, 3]})
    end

    test "a when value may carry a filtered expression with comma-separated args" do
      template = ~s({% case s %}{% when t | replace: "a", "b" %}hit{% else %}miss{% endcase %})
      assert {:ok, "hit"} = render(template, %{"s" => "b", "t" => "a"})
    end
  end
end

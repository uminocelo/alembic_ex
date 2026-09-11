defmodule Alembic.Integration.LiquidCompatTest do
  @moduledoc """
  Liquid-compatibility-style coverage, organized by the same categories the
  official Liquid test suite (github.com/Shopify/liquid) uses. This session
  had no network access to fetch and literally port Shopify's YAML fixtures,
  so these are hand-written cases covering the same categories instead —
  see `COMPATIBILITY.md` for what's supported, what deviates, and what's
  out of scope entirely.
  """

  use ExUnit.Case, async: true

  defp render(template, assigns \\ %{}), do: Alembic.render_string(template, assigns)

  describe "variables" do
    test "simple" do
      assert {:ok, "Alice"} = render("{{ name }}", %{"name" => "Alice"})
    end

    test "dot access" do
      assert {:ok, "Lisbon"} = render("{{ user.city }}", %{"user" => %{"city" => "Lisbon"}})
    end

    test "bracket access" do
      assert {:ok, "Lisbon"} = render(~s({{ user["city"] }}), %{"user" => %{"city" => "Lisbon"}})
    end

    test "undefined renders as empty string" do
      assert {:ok, ""} = render("{{ missing }}")
    end
  end

  describe "if tag" do
    test "truthy/falsy" do
      assert {:ok, "yes"} = render("{% if x %}yes{% else %}no{% endif %}", %{"x" => true})
      assert {:ok, "no"} = render("{% if x %}yes{% else %}no{% endif %}", %{"x" => false})
      assert {:ok, "no"} = render("{% if x %}yes{% else %}no{% endif %}", %{})
    end

    test "comparisons" do
      assert {:ok, "yes"} = render("{% if x == 1 %}yes{% else %}no{% endif %}", %{"x" => 1})
      assert {:ok, "no"} = render("{% if x == 1 %}yes{% else %}no{% endif %}", %{"x" => 2})
    end

    test "contains" do
      assert {:ok, "yes"} =
               render(~s({% if s contains "ell" %}yes{% else %}no{% endif %}), %{"s" => "hello"})
    end

    test "elsif chains" do
      template = "{% if a %}A{% elsif b %}B{% elsif c %}C{% endif %}"
      assert {:ok, "B"} = render(template, %{"b" => true})
    end
  end

  describe "for tag" do
    test "arrays" do
      assert {:ok, "abc"} =
               render("{% for x in xs %}{{ x }}{% endfor %}", %{"xs" => ["a", "b", "c"]})
    end

    test "forloop object" do
      template = "{% for x in xs %}{{ forloop.index }}/{{ forloop.length }} {% endfor %}"
      assert {:ok, "1/2 2/2 "} = render(template, %{"xs" => ["a", "b"]})
    end

    test "break and continue" do
      assert {:ok, "1"} =
               render(
                 "{% for x in xs %}{% if x == 2 %}{% break %}{% endif %}{{ x }}{% endfor %}",
                 %{"xs" => [1, 2, 3]}
               )

      assert {:ok, "13"} =
               render(
                 "{% for x in xs %}{% if x == 2 %}{% continue %}{% endif %}{{ x }}{% endfor %}",
                 %{"xs" => [1, 2, 3]}
               )
    end

    test "break outside a loop is rejected at parse time" do
      assert {:error, {:parser, {:break_outside_loop, %{line: 1, col: 1}}}} =
               render("{% break %}")
    end

    test "range iterable" do
      assert {:ok, "123"} = render("{% for i in (1..3) %}{{ i }}{% endfor %}")
    end

    test "cycle round-robins values" do
      assert {:ok, "abab"} =
               render(~s({% for x in xs %}{% cycle "a", "b" %}{% endfor %}), %{
                 "xs" => [1, 2, 3, 4]
               })
    end
  end

  describe "assign tag" do
    test "basic" do
      assert {:ok, "5"} = render(~s({% assign x = 5 %}{{ x }}))
    end

    test "inside for loops persists after" do
      template = "{% for x in xs %}{% assign last = x %}{% endfor %}{{ last }}"
      assert {:ok, "c"} = render(template, %{"xs" => ["a", "b", "c"]})
    end

    test "made inside an include is visible after it, in the including template" do
      template = ~s({% include "includes/set_flag.html" %}{{ flag }})

      assert {:ok, "set-in-partial"} =
               Alembic.render_string(template, %{}, roots: ["test/fixtures/templates"])
    end
  end

  describe "unless tag" do
    test "renders body on a falsy condition, else otherwise" do
      assert {:ok, "no"} = render("{% unless x %}no{% else %}yes{% endunless %}", %{})
      assert {:ok, "yes"} = render("{% unless x %}no{% else %}yes{% endunless %}", %{"x" => true})
    end

    test "0 is truthy, so the unless body does not render" do
      assert {:ok, "yes"} = render("{% unless n %}no{% else %}yes{% endunless %}", %{"n" => 0})
    end

    test "elsif inside an unless is rejected at parse time" do
      assert {:error, {:parser, {:if_elsif_in_unless, _pos}}} =
               render("{% unless x %}a{% elsif y %}b{% endunless %}")
    end
  end

  describe "case tag" do
    test "multi-value when and else fallthrough" do
      template = "{% case x %}{% when 1, 2 %}low{% else %}high{% endcase %}"
      assert {:ok, "low"} = render(template, %{"x" => 2})
      assert {:ok, "high"} = render(template, %{"x" => 9})
    end

    test "no match and no else renders empty" do
      assert {:ok, ""} = render("{% case x %}{% when 1 %}one{% endcase %}", %{"x" => 5})
    end

    test "else before any when is rejected at parse time" do
      assert {:error, {:parser, {:else_before_when, _pos}}} =
               render("{% case x %}{% else %}e{% when 1 %}a{% endcase %}")
    end
  end

  describe "capture tag" do
    test "captures rendered body and outputs it later" do
      template = "{% capture x %}Hi {{ name }}{% endcapture %}[{{ x }}]"
      assert {:ok, "[Hi Al]"} = render(template, %{"name" => "Al"})
    end

    test "filters apply to a captured variable" do
      template = "{% capture x %}hi{% endcapture %}{{ x | upcase }}"
      assert {:ok, "HI"} = render(template, %{})
    end
  end

  describe "filters" do
    test "all built-in filters handle nil input without crashing" do
      assert {:ok, ""} = render("{{ x | upcase }}", %{})
      assert {:ok, ""} = render("{{ x | strip }}", %{})
    end

    test "empty string input" do
      # Output tags require a variable-path base (documented since
      # Milestone 1.3 — see Alembic.Parser's output_node_from_expr/3);
      # a bare string literal like `"" | upcase` isn't a supported output
      # expression, so route it through a variable instead.
      assert {:ok, ""} = render("{{ empty | upcase }}", %{"empty" => ""})
    end

    test "type coercion" do
      assert {:ok, "42"} = render("{{ x | upcase }}", %{"x" => 42})
    end
  end

  describe "whitespace control" do
    test "all four dash combinations" do
      assert {:ok, "AB"} = render(~s(A{{- x -}}B), %{"x" => ""})
      assert {:ok, "A  B"} = render(~s(A {{ x }} B), %{"x" => ""})
    end
  end

  describe "comments" do
    test "content is discarded entirely" do
      assert {:ok, "beforeafter"} =
               render("before{% comment %}{{ anything }}{% endcomment %}after")
    end
  end

  describe "raw blocks" do
    test "Liquid syntax is preserved as plain text" do
      assert {:ok, "{{ not_a_var }}"} = render("{% raw %}{{ not_a_var }}{% endraw %}")
    end
  end
end

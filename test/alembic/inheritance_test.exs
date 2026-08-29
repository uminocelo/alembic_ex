defmodule Alembic.InheritanceTest do
  use ExUnit.Case, async: true

  alias Alembic.{Context, Evaluator, Inheritance, Lexer, Parser}

  defp compile(source) do
    {:ok, tokens} = Lexer.tokenize(source)
    {:ok, ast} = Parser.parse(tokens)
    ast
  end

  defp render(source, loader_fn, bindings \\ %{}) do
    with {:ok, resolved} <- Inheritance.preprocess(compile(source), loader_fn) do
      Evaluator.eval(resolved, Context.new(bindings))
    end
  end

  describe "collect_blocks/1" do
    test "collects top-level blocks" do
      ast = compile("{% block a %}A{% endblock %}{% block b %}B{% endblock %}")
      assert {:ok, %{"a" => [{:text, "A"}], "b" => [{:text, "B"}]}} = Inheritance.collect_blocks(ast)
    end

    test "collects blocks nested inside if/for" do
      ast =
        compile(
          "{% if x %}{% block a %}A{% endblock %}{% endif %}{% for i in xs %}{% block b %}B{% endblock %}{% endfor %}"
        )

      assert {:ok, %{"a" => [{:text, "A"}], "b" => [{:text, "B"}]}} = Inheritance.collect_blocks(ast)
    end

    test "errors on duplicate block names" do
      ast = compile("{% block a %}1{% endblock %}{% block a %}2{% endblock %}")
      assert {:error, {:duplicate_block, "a"}} = Inheritance.collect_blocks(ast)
    end

    test "empty AST collects no blocks" do
      assert {:ok, %{}} = Inheritance.collect_blocks([])
    end
  end

  describe "resolve/2" do
    test "splices a matching override in place of the block" do
      parent = compile("<a>{% block x %}default{% endblock %}</b>")
      assert [{:text, "<a>"}, {:text, "override"}, {:text, "</b>"}] =
               Inheritance.resolve(parent, %{"x" => [{:text, "override"}]})
    end

    test "keeps the default body when there is no override" do
      parent = compile("{% block x %}default{% endblock %}")
      assert [{:text, "default"}] = Inheritance.resolve(parent, %{})
    end

    test "resolves blocks nested inside if/for" do
      parent = compile("{% if x %}{% block a %}default{% endblock %}{% endif %}")
      [{:if, _cond, then_branch, [], nil}] = Inheritance.resolve(parent, %{"a" => [{:text, "custom"}]})
      assert then_branch == [{:text, "custom"}]
    end
  end

  describe "preprocess/2" do
    test "returns the AST unchanged when there is no extends node" do
      ast = compile("hello {{ name }}")
      assert {:ok, ^ast} = Inheritance.preprocess(ast, fn _ -> {:error, :should_not_be_called} end)
    end
  end

  describe "single-level inheritance" do
    setup do
      base = ~s(<html>{% block title %}Default Title{% endblock %}</html>)

      loader = fn
        "base.html" -> {:ok, base}
        other -> {:error, {:template_not_found, [other]}}
      end

      %{loader: loader}
    end

    test "child block overrides parent block", %{loader: loader} do
      child = ~s({% extends "base.html" %}{% block title %}Custom{% endblock %})
      assert {:ok, "<html>Custom</html>"} = render(child, loader)
    end

    test "unoverridden block uses parent default", %{loader: loader} do
      child = ~s({% extends "base.html" %})
      assert {:ok, "<html>Default Title</html>"} = render(child, loader)
    end

    test "block.super renders parent content inside the child override", %{loader: loader} do
      child = ~s({% extends "base.html" %}{% block title %}Prefix - {{ block.super }}{% endblock %})
      assert {:ok, "<html>Prefix - Default Title</html>"} = render(child, loader)
    end
  end

  describe "multi-level inheritance chain" do
    test "three levels: each ancestor's blocks are visible unless overridden closer to the child" do
      grandparent = ~s(<h>{% block title %}GPTitle{% endblock %}</h><b>{% block content %}GPContent{% endblock %}</b>)
      parent = ~s({% extends "grandparent.html" %}{% block content %}ParentContent{% endblock %})
      child = ~s({% extends "parent.html" %}{% block title %}ChildTitle{% endblock %})

      loader = fn
        "grandparent.html" -> {:ok, grandparent}
        "parent.html" -> {:ok, parent}
      end

      assert {:ok, "<h>ChildTitle</h><b>ParentContent</b>"} = render(child, loader)
    end

    test "a block untouched at every level keeps the root ancestor's default" do
      grandparent = ~s({% block a %}root-a{% endblock %}{% block b %}root-b{% endblock %})
      parent = ~s({% extends "grandparent.html" %}{% block a %}parent-a{% endblock %})
      child = ~s({% extends "parent.html" %})

      loader = fn
        "grandparent.html" -> {:ok, grandparent}
        "parent.html" -> {:ok, parent}
      end

      assert {:ok, "parent-aroot-b"} = render(child, loader)
    end
  end

  describe "circular inheritance detection" do
    test "A extends B extends A returns a structured error" do
      loader = fn
        "a.html" -> {:ok, ~s({% extends "b.html" %})}
        "b.html" -> {:ok, ~s({% extends "a.html" %})}
      end

      ast_a = compile(~s({% extends "b.html" %}))
      assert {:error, {:circular_inheritance, "b.html"}} = Inheritance.resolve_chain(ast_a, loader)
    end

    test "a template that extends itself is caught" do
      loader = fn "self.html" -> {:ok, ~s({% extends "self.html" %})} end
      ast = compile(~s({% extends "self.html" %}))
      assert {:error, {:circular_inheritance, "self.html"}} = Inheritance.resolve_chain(ast, loader)
    end
  end

  describe "maximum depth" do
    test "a chain deeper than the 10-level default returns a structured error" do
      loader = fn "t" <> rest ->
        n = rest |> String.trim_trailing(".html") |> String.to_integer()
        {:ok, ~s({% extends "t#{n + 1}.html" %})}
      end

      ast = compile(~s({% extends "t1.html" %}))
      assert {:error, :inheritance_depth_exceeded} = Inheritance.resolve_chain(ast, loader)
    end
  end

  describe "missing parent template" do
    test "propagates the loader's error unchanged" do
      loader = fn name -> {:error, {:template_not_found, [name]}} end
      child = ~s({% extends "missing.html" %})
      assert {:error, {:template_not_found, ["missing.html"]}} = render(child, loader)
    end
  end

  describe "purity" do
    test "resolve_chain never touches the file system — only the injected loader is called" do
      calls = :counters.new(1, [])

      loader = fn "base.html" ->
        :counters.add(calls, 1, 1)
        {:ok, "<html>{% block x %}d{% endblock %}</html>"}
      end

      child = ~s({% extends "base.html" %})
      assert {:ok, "<html>d</html>"} = render(child, loader)
      assert :counters.get(calls, 1) == 1
    end
  end
end

defmodule Alembic.ParserTest do
  use ExUnit.Case, async: true

  doctest Alembic.Parser

  alias Alembic.{Lexer, Parser}

  defp parse(source) do
    {:ok, tokens} = Lexer.tokenize(source)
    Parser.parse(tokens)
  end

  describe "text and output nodes" do
    test "plain text" do
      assert {:ok, [{:text, "hello"}]} = parse("hello")
    end

    test "simple output" do
      assert {:ok, [{:output, ["name"], []}]} = parse("{{ name }}")
    end

    test "dot-path output" do
      assert {:ok, [{:output, ["user", "name"], []}]} = parse("{{ user.name }}")
    end

    test "output with a filter chain" do
      assert {:ok, [{:output, ["name"], [{:filter, "upcase", []}]}]} =
               parse("{{ name | upcase }}")
    end

    test "output with a non-variable base is rejected" do
      assert {:error, {:unsupported_output_expression, _raw}} = parse(~s({{ "literal" }}))
    end
  end

  describe "whitespace control" do
    test "strip_left trims trailing whitespace off the preceding text" do
      assert {:ok, [{:text, "Hello"}, {:output, ["name"], []}]} = parse("Hello   {{- name }}")
    end

    test "strip_right trims leading whitespace off the following text" do
      assert {:ok, [{:output, ["name"], []}, {:text, "World"}]} = parse("{{ name -}}   World")
    end

    test "strip on both sides of a tag trims both neighbors" do
      assert {:ok, [{:text, "Hello"}, {:if, _cond, [{:text, "yes"}], [], nil}, {:text, "World"}]} =
               parse("Hello \n  {%- if x %}yes{% endif -%}\n  World")
    end

    test "no adjacent text token is a no-op, not an error" do
      assert {:ok, [{:output, ["name"], []}]} = parse("{{- name -}}")
    end

    test "without strip markers, surrounding whitespace is preserved" do
      assert {:ok, [{:text, "Hello   "}, {:output, ["name"], []}, {:text, "   World"}]} =
               parse("Hello   {{ name }}   World")
    end
  end

  describe "if block" do
    test "if with else" do
      assert {:ok, [{:if, _condition, [{:text, "yes"}], [], [{:text, "no"}]}]} =
               parse("{% if x %}yes{% else %}no{% endif %}")
    end

    test "if without else" do
      assert {:ok, [{:if, _condition, [{:text, "yes"}], [], nil}]} =
               parse("{% if x %}yes{% endif %}")
    end

    test "if with elsif chain and else" do
      assert {:ok,
              [
                {:if, _cond, [{:text, "a"}],
                 [{_elsif1_cond, [{:text, "b"}]}, {_elsif2_cond, [{:text, "c"}]}], [{:text, "d"}]}
              ]} = parse("{% if x %}a{% elsif y %}b{% elsif z %}c{% else %}d{% endif %}")
    end

    test "missing endif returns a structured error" do
      assert {:error, {:missing_end_tag, "endif"}} = parse("{% if x %}no closing tag")
    end
  end

  describe "for block" do
    test "for with output body, forloop metadata accessible as a path" do
      assert {:ok, [{:for, "item", {:variable, ["list"]}, [{:output, ["item"], []}], nil}]} =
               parse("{% for item in list %}{{ item }}{% endfor %}")
    end

    test "for with else branch" do
      assert {:ok, [{:for, "post", _iterable, _body, [{:text, "empty"}]}]} =
               parse("{% for post in posts %}{{ post }}{% else %}empty{% endfor %}")
    end

    test "missing endfor returns a structured error" do
      assert {:error, {:missing_end_tag, "endfor"}} = parse("{% for x in xs %}no closing tag")
    end

    test "malformed for (missing ' in ') returns a structured error" do
      assert {:error, {:malformed_for, _spec}} = parse("{% for x %}body{% endfor %}")
    end
  end

  describe "nested blocks" do
    test "for inside if" do
      assert {:ok, [{:if, _cond, [{:for, "i", _it, _body, nil}], [], nil}]} =
               parse("{% if x %}{% for i in xs %}{{ i }}{% endfor %}{% endif %}")
    end

    test "if inside for" do
      assert {:ok, [{:for, _var, _it, [{:if, _cond, _then, [], nil}], nil}]} =
               parse("{% for i in xs %}{% if i %}ok{% endif %}{% endfor %}")
    end
  end

  describe "assign tag" do
    test "parses assign and makes the value available to later output" do
      assert {:ok, [{:assign, "x", {:literal, 5}}, {:output, ["x"], []}]} =
               parse("{% assign x = 5 %}{{ x }}")
    end

    test "malformed assign returns a structured error" do
      assert {:error, {:malformed_assign, _reason}} = parse("{% assign x %}")
    end
  end

  describe "template inheritance" do
    test "extends as the first node" do
      assert {:ok, [{:extends, "base.html"}]} = parse(~s({% extends "base.html" %}))
    end

    test "extends must be first" do
      assert {:error, :extends_not_first} = parse(~s(some text{% extends 'base.html' %}))
    end

    test "block with nested content" do
      assert {:ok, [{:block, "title", [{:text, "Hi"}]}]} =
               parse("{% block title %}Hi{% endblock %}")
    end

    test "extends followed by block overrides" do
      assert {:ok, [{:extends, "base.html"}, {:block, "title", [{:text, "Hi"}]}]} =
               parse(~s({% extends "base.html" %}{% block title %}Hi{% endblock %}))
    end

    test "missing endblock returns a structured error" do
      assert {:error, {:missing_end_tag, "endblock"}} = parse("{% block title %}no closing tag")
    end
  end

  describe "include tag" do
    test "include without variables" do
      assert {:ok, [{:include, "header.html", %{}}]} = parse(~s({% include "header.html" %}))
    end

    test "include with variables" do
      assert {:ok, [{:include, "header.html", variables}]} =
               parse(~s({% include "header.html" with title: "Hello", count: 3 %}))

      assert variables == %{"title" => {:literal, "Hello"}, "count" => {:literal, 3}}
    end
  end

  describe "errors" do
    test "unexpected trailing token" do
      assert {:error, {:unexpected_token, {:tag, "endif", false, false}}} =
               parse("{% endif %}")
    end

    test "unknown tag keyword" do
      assert {:error, {:unexpected_tag, "frobnicate x"}} = parse("{% frobnicate x %}")
    end

    test "invalid expression inside output propagates the expression parser's error" do
      assert {:error, {:invalid_expression, _raw, {:unknown_operator, "**"}}} =
               parse("{{ x ** y }}")
    end
  end

  describe "grammar worked example" do
    test "for/if/output/filter nesting from docs/grammar.md" do
      template = """
      {% for post in site.posts %}
        <h2>{{ post.title | upcase }}</h2>
        {% if post.featured %}★{% endif %}
      {% endfor %}\
      """

      assert {:ok,
              [
                {:for, "post", {:variable, ["site", "posts"]},
                 [
                   {:text, "\n  <h2>"},
                   {:output, ["post", "title"], [{:filter, "upcase", []}]},
                   {:text, "</h2>\n  "},
                   {:if, {:variable, ["post", "featured"]}, [{:text, "★"}], [], nil},
                   {:text, "\n"}
                 ], nil}
              ]} = parse(template)
    end
  end
end

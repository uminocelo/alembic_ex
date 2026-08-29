defmodule Alembic.LexerTest do
  use ExUnit.Case, async: true

  doctest Alembic.Lexer

  alias Alembic.Lexer

  describe "tokenize/2" do
    test "tokenize an empty template" do
      assert {:ok, []} == Lexer.tokenize("")
    end

    test "tokenizes plain text" do
      assert {:ok, [{:text, "hello"}]} = Lexer.tokenize("hello")
    end

    test "tokenizes an output  expressions" do
      assert {:ok, [{:output, "name", false, false}]} = Lexer.tokenize("{{ name }}")
    end

    test "trims whitespace around output expressions" do
      assert {:ok, [{:output, "user.name", false, false}]} = Lexer.tokenize("{{   user.name   }}")
    end

    test "tokenizes mixed test and output expressions" do
      assert {:ok, [{:text, "Hi "}, {:output, "name", false, false}, {:text, "!"}]} =
               Lexer.tokenize("Hi {{ name }}!")
    end

    test "tokenizes block tags" do
      assert {:ok, [{:tag, "if user.name", false, false}]} = Lexer.tokenize("{% if user.name %}")
    end

    test "tokenizes multiple tag type" do
      template = "{% if user.name %}Hello {{ user.name }}{% endif %}"

      assert {:ok,
              [
                {:tag, "if user.name", false, false},
                {:text, "Hello "},
                {:output, "user.name", false, false},
                {:tag, "endif", false, false}
              ]} =
               Lexer.tokenize(template)
    end
  end

  describe "text coalescing" do
    test "coalesce adjacent characteres into one text token" do
      assert {:ok, [{:text, "Hello world"}]} = Lexer.tokenize("Hello world")
    end

    test "keeps text separeted by template expressions" do
      assert {:ok, [{:text, "Hello "}, {:output, "name", false, false}, {:text, ", welcome!"}]} =
               Lexer.tokenize("Hello {{ name }}, welcome!")
    end
  end

  describe "UTF-8" do
    test "preserves accented latin text" do
      assert {:ok, [{:text, "Olá, você!"}]} = Lexer.tokenize("Olá, você!")
    end

    test "preserves arabic text" do
      assert {:ok, [{:text, "مرحبا"}]} = Lexer.tokenize("مرحبا")
    end

    test "preserves CJK text" do
      assert {:ok, [{:text, "こんにちは"}]} = Lexer.tokenize("こんにちは")
    end

    test "preserves emojis" do
      assert {:ok, [{:text, "Hello 👋🌎"}]} = Lexer.tokenize("Hello 👋🌎")
    end

    test "tokenizes expressions after multibyte text" do
      assert {:ok, [{:text, "こんにちは"}, {:output, "name", false, false}]} =
               Lexer.tokenize("こんにちは{{ name }}")
    end

    test "multiple UTF-8 scripts" do
      template = "Olá مرحبا こんにちは 👋 {{ name }}"

      assert {:ok, [{:text, "Olá مرحبا こんにちは 👋 "}, {:output, "name", false, false}]} =
               Lexer.tokenize(template)
    end
  end

  describe "whitespace control" do
    test "strips left on output tags" do
      assert {:ok, [{:output, "name", true, false}]} = Lexer.tokenize("{{- name }}")
    end

    test "strips right on output tags" do
      assert {:ok, [{:output, "name", false, true}]} = Lexer.tokenize("{{ name -}}")
    end

    test "strips both sides on output tags" do
      assert {:ok, [{:output, "name", true, true}]} = Lexer.tokenize("{{- name -}}")
    end

    test "no stripping on plain output tags" do
      assert {:ok, [{:output, "name", false, false}]} = Lexer.tokenize("{{ name }}")
    end

    test "strips left on tag tokens" do
      assert {:ok, [{:tag, "if x", true, false}]} = Lexer.tokenize("{%- if x %}")
    end

    test "strips right on tag tokens" do
      assert {:ok, [{:tag, "if x", false, true}]} = Lexer.tokenize("{% if x -%}")
    end

    test "strips both sides on tag tokens" do
      assert {:ok, [{:tag, "if x", true, true}]} = Lexer.tokenize("{%- if x -%}")
    end

    test "no stripping on plain tag tokens" do
      assert {:ok, [{:tag, "if x", false, false}]} = Lexer.tokenize("{% if x %}")
    end

    test "strip markers do not leak into trimmed content" do
      assert {:ok, [{:output, "user.name", true, true}]} = Lexer.tokenize("{{- user.name -}}")
    end
  end

  describe "comment blocks" do
    test "emits no tokens for a comment block" do
      assert {:ok, []} = Lexer.tokenize("{% comment %}ignored{% endcomment %}")
    end

    test "discards surrounding whitespace-stripped comment delimiters" do
      assert {:ok, []} = Lexer.tokenize("{%- comment -%}ignored{%- endcomment -%}")
    end

    test "discards Liquid-like syntax inside a comment block" do
      assert {:ok, [{:text, "beforeafter"}]} =
               Lexer.tokenize("before{% comment %}{{ not_a_variable }}{% endcomment %}after")
    end

    test "comment block surrounded by text coalesces correctly" do
      assert {:ok, [{:text, "beforeafter"}]} =
               Lexer.tokenize("before{% comment %}nope{% endcomment %}after")
    end

    test "unterminated comment block returns a structured error" do
      assert {:error, {:unterminated_comment, %{line: 1, col: 1}}} =
               Lexer.tokenize("{% comment %}never closed")
    end
  end

  describe "raw blocks" do
    test "emits raw block content as a single text token" do
      assert {:ok, [{:text, "  {{ this_is_not_a_variable }}  "}]} =
               Lexer.tokenize("{% raw %}  {{ this_is_not_a_variable }}  {% endraw %}")
    end

    test "does not tokenize Liquid syntax inside a raw block" do
      assert {:ok, [{:text, "{% if x %}{{ y }}{% endif %}"}]} =
               Lexer.tokenize("{% raw %}{% if x %}{{ y }}{% endif %}{% endraw %}")
    end

    test "empty raw block emits no tokens" do
      assert {:ok, []} = Lexer.tokenize("{% raw %}{% endraw %}")
    end

    test "raw block content coalesces with surrounding text" do
      assert {:ok, [{:text, "before{{ raw }}after"}]} =
               Lexer.tokenize("before{% raw %}{{ raw }}{% endraw %}after")
    end

    test "unterminated raw block returns a structured error" do
      assert {:error, {:unterminated_raw, %{line: 1, col: 1}}} =
               Lexer.tokenize("{% raw %}never closed")
    end
  end

  describe "line and column tracking" do
    test "tracks line and column across newlines" do
      template = "line one\nline two {{ name"

      assert {:error, {:unterminated_output, %{line: 2, col: 10}}} = Lexer.tokenize(template)
    end

    test "resets column on each newline" do
      template = "\n\n{{ name"

      assert {:error, {:unterminated_output, %{line: 3, col: 1}}} = Lexer.tokenize(template)
    end
  end

  describe "errors" do
    test "returns an error  for unterminated output expressions" do
      assert {:error, {:unterminated_output, %{line: 1, col: 1}}} = Lexer.tokenize("{{ name")
    end

    test "returns an error for unterminated block tags" do
      assert {:error, {:unterminated_tag, %{line: 1, col: 1}}} = Lexer.tokenize("{% if user.admin")
    end

    test "returns the position of an unterminated output expression" do
      assert {:error, {:unterminated_output, %{line: 1, col: 7}}} = Lexer.tokenize("Hello {{ name")
    end

    test "returns character position instead of byte offserts" do
      assert {:error, {:unterminated_output, %{line: 1, col: 7}}} = Lexer.tokenize("Olá 🙂 {{ name")
    end

    test "rejects an empty output expressions" do
      assert {:error, {:empty_output_tag, %{line: 1, col: 1}}} = Lexer.tokenize("{{ }}")
    end

    test "rejcets an output expressions containing only whitespaces" do
      assert {:error, {:empty_output_tag, %{line: 1, col: 5}}} = Lexer.tokenize("abc {{    }}")
    end
  end

  describe "property: tokenize/reconstruct roundtrip" do
    test "reconstructing 1000 generated canonical templates yields the original source" do
      for _ <- 1..1000 do
        source = Alembic.LexerGenerators.random_canonical_template()

        assert {:ok, tokens} = Lexer.tokenize(source)
        assert Alembic.LexerGenerators.reconstruct(tokens) == source
      end
    end
  end
end

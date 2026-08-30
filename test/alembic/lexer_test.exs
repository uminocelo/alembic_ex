defmodule Alembic.LexerTest do
  use ExUnit.Case, async: true

  doctest Alembic.Lexer

  alias Alembic.Lexer

  describe "tokenize/2" do
    test "tokenize an empty template" do
      assert {:ok, []} == Lexer.tokenize("")
    end

    test "tokenizes plain text" do
      assert {:ok, [{:text, "hello", _pos}]} = Lexer.tokenize("hello")
    end

    test "tokenizes an output  expressions" do
      assert {:ok, [{:output, "name", false, false, _pos}]} = Lexer.tokenize("{{ name }}")
    end

    test "trims whitespace around output expressions" do
      assert {:ok, [{:output, "user.name", false, false, _pos}]} =
               Lexer.tokenize("{{   user.name   }}")
    end

    test "tokenizes mixed test and output expressions" do
      assert {:ok, [{:text, "Hi ", _p1}, {:output, "name", false, false, _p2}, {:text, "!", _p3}]} =
               Lexer.tokenize("Hi {{ name }}!")
    end

    test "tokenizes block tags" do
      assert {:ok, [{:tag, "if user.name", false, false, _pos}]} =
               Lexer.tokenize("{% if user.name %}")
    end

    test "tokenizes multiple tag type" do
      template = "{% if user.name %}Hello {{ user.name }}{% endif %}"

      assert {:ok,
              [
                {:tag, "if user.name", false, false, _p1},
                {:text, "Hello ", _p2},
                {:output, "user.name", false, false, _p3},
                {:tag, "endif", false, false, _p4}
              ]} =
               Lexer.tokenize(template)
    end
  end

  describe "text coalescing" do
    test "coalesce adjacent characteres into one text token" do
      assert {:ok, [{:text, "Hello world", _pos}]} = Lexer.tokenize("Hello world")
    end

    test "keeps text separeted by template expressions" do
      assert {:ok,
              [
                {:text, "Hello ", _p1},
                {:output, "name", false, false, _p2},
                {:text, ", welcome!", _p3}
              ]} =
               Lexer.tokenize("Hello {{ name }}, welcome!")
    end

    test "coalesced text keeps the position of its first character" do
      assert {:ok, [{:text, "Hello world", %{line: 1, col: 1}}]} = Lexer.tokenize("Hello world")
    end
  end

  describe "UTF-8" do
    test "preserves accented latin text" do
      assert {:ok, [{:text, "Olá, você!", _pos}]} = Lexer.tokenize("Olá, você!")
    end

    test "preserves arabic text" do
      assert {:ok, [{:text, "مرحبا", _pos}]} = Lexer.tokenize("مرحبا")
    end

    test "preserves CJK text" do
      assert {:ok, [{:text, "こんにちは", _pos}]} = Lexer.tokenize("こんにちは")
    end

    test "preserves emojis" do
      assert {:ok, [{:text, "Hello 👋🌎", _pos}]} = Lexer.tokenize("Hello 👋🌎")
    end

    test "tokenizes expressions after multibyte text" do
      assert {:ok, [{:text, "こんにちは", _p1}, {:output, "name", false, false, _p2}]} =
               Lexer.tokenize("こんにちは{{ name }}")
    end

    test "multiple UTF-8 scripts" do
      template = "Olá مرحبا こんにちは 👋 {{ name }}"

      assert {:ok, [{:text, "Olá مرحبا こんにちは 👋 ", _p1}, {:output, "name", false, false, _p2}]} =
               Lexer.tokenize(template)
    end

    test "reports column position by character, not byte, across multibyte text" do
      assert {:ok, [{:text, "Olá ", %{line: 1, col: 1}}, {:output, "name", false, false, pos}]} =
               Lexer.tokenize("Olá {{ name }}")

      assert pos == %{line: 1, col: 5}
    end
  end

  describe "whitespace control" do
    test "strips left on output tags" do
      assert {:ok, [{:output, "name", true, false, _pos}]} = Lexer.tokenize("{{- name }}")
    end

    test "strips right on output tags" do
      assert {:ok, [{:output, "name", false, true, _pos}]} = Lexer.tokenize("{{ name -}}")
    end

    test "strips both sides on output tags" do
      assert {:ok, [{:output, "name", true, true, _pos}]} = Lexer.tokenize("{{- name -}}")
    end

    test "no stripping on plain output tags" do
      assert {:ok, [{:output, "name", false, false, _pos}]} = Lexer.tokenize("{{ name }}")
    end

    test "strips left on tag tokens" do
      assert {:ok, [{:tag, "if x", true, false, _pos}]} = Lexer.tokenize("{%- if x %}")
    end

    test "strips right on tag tokens" do
      assert {:ok, [{:tag, "if x", false, true, _pos}]} = Lexer.tokenize("{% if x -%}")
    end

    test "strips both sides on tag tokens" do
      assert {:ok, [{:tag, "if x", true, true, _pos}]} = Lexer.tokenize("{%- if x -%}")
    end

    test "no stripping on plain tag tokens" do
      assert {:ok, [{:tag, "if x", false, false, _pos}]} = Lexer.tokenize("{% if x %}")
    end

    test "strip markers do not leak into trimmed content" do
      assert {:ok, [{:output, "user.name", true, true, _pos}]} =
               Lexer.tokenize("{{- user.name -}}")
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
      assert {:ok, [{:text, "beforeafter", _pos}]} =
               Lexer.tokenize("before{% comment %}{{ not_a_variable }}{% endcomment %}after")
    end

    test "comment block surrounded by text coalesces correctly" do
      assert {:ok, [{:text, "beforeafter", _pos}]} =
               Lexer.tokenize("before{% comment %}nope{% endcomment %}after")
    end

    test "unterminated comment block returns a structured error" do
      assert {:error, {:unterminated_comment, %{line: 1, col: 1}}} =
               Lexer.tokenize("{% comment %}never closed")
    end
  end

  describe "raw blocks" do
    test "emits raw block content as a single text token" do
      assert {:ok, [{:text, "  {{ this_is_not_a_variable }}  ", _pos}]} =
               Lexer.tokenize("{% raw %}  {{ this_is_not_a_variable }}  {% endraw %}")
    end

    test "does not tokenize Liquid syntax inside a raw block" do
      assert {:ok, [{:text, "{% if x %}{{ y }}{% endif %}", _pos}]} =
               Lexer.tokenize("{% raw %}{% if x %}{{ y }}{% endif %}{% endraw %}")
    end

    test "empty raw block emits no tokens" do
      assert {:ok, []} = Lexer.tokenize("{% raw %}{% endraw %}")
    end

    test "raw block content coalesces with surrounding text" do
      assert {:ok, [{:text, "before{{ raw }}after", _pos}]} =
               Lexer.tokenize("before{% raw %}{{ raw }}{% endraw %}after")
    end

    test "raw block content position points at the first char after the opening tag" do
      assert {:ok, [{:text, "hi", pos}]} = Lexer.tokenize("{% raw %}hi{% endraw %}")
      assert pos == %{line: 1, col: 10}
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

    test "tag and output tokens carry the position of their opening delimiter" do
      template = "line one\nline two {% if x %}{{ y }}"

      assert {:ok,
              [
                {:text, _text, _pos},
                {:tag, "if x", false, false, tag_pos},
                {:output, "y", false, false, out_pos}
              ]} =
               Lexer.tokenize(template)

      assert tag_pos == %{line: 2, col: 10}
      assert out_pos == %{line: 2, col: 20}
    end
  end

  describe "errors" do
    test "returns an error  for unterminated output expressions" do
      assert {:error, {:unterminated_output, %{line: 1, col: 1}}} = Lexer.tokenize("{{ name")
    end

    test "returns an error for unterminated block tags" do
      assert {:error, {:unterminated_tag, %{line: 1, col: 1}}} =
               Lexer.tokenize("{% if user.admin")
    end

    test "returns the position of an unterminated output expression" do
      assert {:error, {:unterminated_output, %{line: 1, col: 7}}} =
               Lexer.tokenize("Hello {{ name")
    end

    test "returns character position instead of byte offserts" do
      assert {:error, {:unterminated_output, %{line: 1, col: 7}}} =
               Lexer.tokenize("Olá 🙂 {{ name")
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

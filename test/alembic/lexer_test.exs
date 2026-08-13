defmodule Alembic.LexerTest do
  use ExUnit.Case, async: true

  alias Alembic.Lexer

  describe "tokenize/2" do
    test "tokenize an empty template" do
      assert {:ok, []} == Lexer.tokenize("")
    end

    test "tokenizes plain text" do
      assert {:ok, [{:text, "hello"}]} = Lexer.tokenize("hello")
    end

    test "tokenizes an output  expressions" do
      assert {:ok, [{:output, "name"}]} = Lexer.tokenize("{{ name }}")
    end

    test "trims whitespace around output expressions" do
      assert {:ok, [{:output, "user.name"}]} = Lexer.tokenize("{{   user.name   }}")
    end

    test "tokenizes mixed test and output expressions" do
      assert {:ok, [{:text, "Hi "}, {:output, "name"}, {:text, "!"}]} =
               Lexer.tokenize("Hi {{ name }}!")
    end

    test "tokenizes block tags" do
      assert {:ok, [{:tag, "if user.name"}]} = Lexer.tokenize("{% if user.name %}")
    end

    test "tokenizes multiple tag type" do
      template = "{% if user.name %}Hello {{ user.name }}{% endif %}"

      assert {:ok,
              [
                {:tag, "if user.name"},
                {:text, "Hello "},
                {:output, "user.name"},
                {:tag, "endif"}
              ]} =
               Lexer.tokenize(template)
    end
  end

  describe "text coalescing" do
    test "coalesce adjacent characteres into one text token" do
      assert {:ok, [{:text, "Hello world"}]} = Lexer.tokenize("Hello world")
    end

    test "keeps text separeted by template expressions" do
      assert {:ok, [{:text, "Hello "}, {:output, "name"}, {:text, ", welcome!"}]} =
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
      assert {:ok, [{:text, "こんにちは"}, {:output, "name"}]} = Lexer.tokenize("こんにちは{{ name }}")
    end

    test "multiple UTF-8 scripts" do
      template = "Olá مرحبا こんにちは 👋 {{ name }}"

      assert {:ok, [{:text, "Olá مرحبا こんにちは 👋 "}, {:output, "name"}]} = Lexer.tokenize(template)
    end
  end

  describe "errors" do
    test "returns an error  for unterminated output expressions" do
      assert {:error, {:unterminated_output, 0}} = Lexer.tokenize("{{ name")
    end

    test "returns an error for unterminated block tags" do
      assert {:error, {:unterminated_tag, 0}} = Lexer.tokenize("{% if user.admin")
    end

    test "returns the position of an unterminated output expression" do
      assert {:error, {:unterminated_output, 6}} = Lexer.tokenize("Hello {{ name")
    end

    test "returns character position instead of byte offserts" do
      assert {:error, {:unterminated_output, 6}} = Lexer.tokenize("Olá 🙂 {{ name")
    end

    test "rejects an empty output expressions" do
      assert {:error, {:empty_output_tag, 0}} = Lexer.tokenize("{{ }}")
    end

    test "rejcets an output expressions containing only whitespaces" do
      assert {:error, {:empty_output_tag, 4}} = Lexer.tokenize("abc {{    }}")
    end
  end
end

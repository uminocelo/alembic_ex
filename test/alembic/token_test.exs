defmodule Alembic.TokenTest do
  use ExUnit.Case, async: true

  doctest Alembic.Token

  alias Alembic.Token

  describe "token shapes" do
    test "represents raw text" do
      token = text_token("Hello, world!")
      assert {:text, "Hello, world!", %{line: 1, col: 1}} = token
    end

    test "represents output expressions" do
      token = output_token("user.name | upcase")

      assert {:output, "user.name | upcase", false, false, %{line: 1, col: 1}} = token
    end

    test "represents block tags" do
      opening_token = tag_token("if user.admin")
      closing_token = tag_token("endif")

      assert {:tag, "if user.admin", false, false, %{line: 1, col: 1}} = opening_token
      assert {:tag, "endif", false, false, %{line: 1, col: 1}} = closing_token
    end

    test "represents whitespace-stripped output tokens" do
      assert {:output, "name", true, true, _pos} = output_token("name", true, true)
      assert {:output, "name", true, false, _pos} = output_token("name", true, false)
      assert {:output, "name", false, true, _pos} = output_token("name", false, true)
    end

    test "represents whitespace-stripped tag tokens" do
      assert {:tag, "if x", true, true, _pos} = tag_token("if x", true, true)
      assert {:tag, "if x", true, false, _pos} = tag_token("if x", true, false)
      assert {:tag, "if x", false, true, _pos} = tag_token("if x", false, true)
    end
  end

  describe "position/1" do
    test "extracts the position from any token shape" do
      assert Token.position({:text, "hi", %{line: 2, col: 3}}) == %{line: 2, col: 3}
      assert Token.position(output_token("name")) == %{line: 1, col: 1}
      assert Token.position(tag_token("endif")) == %{line: 1, col: 1}
    end
  end

  @spec text_token(String.t()) :: Token.t()
  defp text_token(content), do: {:text, content, %{line: 1, col: 1}}

  @spec output_token(String.t(), boolean(), boolean()) :: Token.t()
  defp output_token(expression, strip_left \\ false, strip_right \\ false),
    do: {:output, expression, strip_left, strip_right, %{line: 1, col: 1}}

  @spec tag_token(String.t(), boolean(), boolean()) :: Token.t()
  defp tag_token(statement, strip_left \\ false, strip_right \\ false),
    do: {:tag, statement, strip_left, strip_right, %{line: 1, col: 1}}
end

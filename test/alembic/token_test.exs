defmodule Alembic.TokenTest do
  use ExUnit.Case, async: true

  alias Alembic.Token

  describe "token shapes" do
    test "represents raw text" do
      token = text_token("Hello, world!")
      assert {:text, "Hello, world!"} = token
    end

    test "represents output expressions" do
      token = output_token("user.name | upcase")

      assert {:output, "user.name | upcase", false, false} = token
    end

    test "represents block tags" do
      opening_token = tag_token("if user.admin")
      closing_token = tag_token("endif")

      assert {:tag, "if user.admin", false, false} = opening_token
      assert {:tag, "endif", false, false} = closing_token
    end

    test "represents whitespace-stripped output tokens" do
      assert {:output, "name", true, true} = output_token("name", true, true)
      assert {:output, "name", true, false} = output_token("name", true, false)
      assert {:output, "name", false, true} = output_token("name", false, true)
    end

    test "represents whitespace-stripped tag tokens" do
      assert {:tag, "if x", true, true} = tag_token("if x", true, true)
      assert {:tag, "if x", true, false} = tag_token("if x", true, false)
      assert {:tag, "if x", false, true} = tag_token("if x", false, true)
    end
  end

  @spec text_token(String.t()) :: Token.t()
  defp text_token(content), do: {:text, content}

  @spec output_token(String.t(), boolean(), boolean()) :: Token.t()
  defp output_token(expression, strip_left \\ false, strip_right \\ false),
    do: {:output, expression, strip_left, strip_right}

  @spec tag_token(String.t(), boolean(), boolean()) :: Token.t()
  defp tag_token(statement, strip_left \\ false, strip_right \\ false),
    do: {:tag, statement, strip_left, strip_right}
end

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

      assert {:output, "user.name | upcase"} = token
    end

    test "represents block tags" do
      opening_token = tag_token("if user.admin")
      closing_token = tag_token("endif")

      assert {:tag, "if user.admin"} = opening_token
      assert {:tag, "endif"} = closing_token
    end
  end

  @spec text_token(String.t()) :: Token.t()
  defp text_token(content), do: {:text, content}

  @spec output_token(String.t()) :: Token.t()
  defp output_token(expression), do: {:output, expression}

  @spec tag_token(String.t()) :: Token.t()
  defp tag_token(statement), do: {:tag, statement}
end

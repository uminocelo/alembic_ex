defmodule Alembic.Integration.PropertyTest do
  @moduledoc """
  Property-based tests for the full pipeline (manual generators — no
  `:proper`/`StreamData` dependency, keeping the zero-runtime-deps policy;
  dev/test deps are unaffected by that policy, but this doesn't even need
  one).
  """

  use ExUnit.Case, async: true

  @text_chars ["a", "b", "c", " ", "1", "!", "Olá", "こんにちは", "👋"]

  test "text-only templates (no Liquid delimiters) always round-trip through render_string/3 unchanged" do
    for _ <- 1..500 do
      text = random_text()
      assert {:ok, ^text} = Alembic.render_string(text)
    end
  end

  test "variable output with no filters always returns the string form of the bound value" do
    for _ <- 1..500 do
      {value, expected} = random_scalar()
      assert {:ok, ^expected} = Alembic.render_string("{{ v }}", %{"v" => value})
    end
  end

  test "compile/2 then render/3 equals render_string/3 for the same source and context" do
    for _ <- 1..500 do
      text = random_text()
      source = "prefix-#{text}-{{ v }}-suffix"
      {value, _expected} = random_scalar()
      assigns = %{"v" => value}

      {:ok, ast} = Alembic.compile(source)
      assert Alembic.render(ast, assigns) == Alembic.render_string(source, assigns)
    end
  end

  defp random_text do
    1..Enum.random(0..10)//1
    |> Enum.map_join(fn _ -> Enum.random(@text_chars) end)
  end

  defp random_scalar do
    case Enum.random([:string, :int, :float, :bool, nil]) do
      :string ->
        s = random_text()
        {s, s}

      :int ->
        n = Enum.random(-1000..1000)
        {n, Integer.to_string(n)}

      :float ->
        n = Enum.random(-1000..1000) / 7
        {n, Float.to_string(n)}

      :bool ->
        b = Enum.random([true, false])
        {b, to_string(b)}

      nil ->
        {nil, ""}
    end
  end
end

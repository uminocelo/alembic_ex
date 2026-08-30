defmodule Alembic.Integration.ErrorHandlingTest do
  @moduledoc """
  Verifies that errors from deep in the pipeline (Lexer, Parser, Loader,
  Evaluator) surface cleanly through the public `Alembic` API, tagged with
  which pipeline stage they came from, rather than leaking a raw exception.
  """

  use ExUnit.Case, async: true

  @templates_root "test/fixtures/templates"

  test "a Lexer error (unterminated tag) surfaces from render_string/3 cleanly" do
    assert {:error, {:lexer, {:unterminated_output, %{line: 1, col: 1}}}} =
             Alembic.render_string("{{ name")
  end

  test "a Parser error (missing endif) surfaces from render_string/3 with line/col information" do
    assert {:error, {:parser, {:missing_end_tag, "endif", %{line: 1, col: 1}}}} =
             Alembic.render_string("{% if x %}no closing tag")
  end

  test "a Loader error (missing file) surfaces from render_file/3 cleanly" do
    assert {:error, {:loader, {:template_not_found, paths}}} =
             Alembic.render_file("nope.html", %{}, roots: [@templates_root])

    assert Enum.any?(paths, &String.ends_with?(&1, "nope.html"))
  end

  test "bang variants wrap every error in Alembic.TemplateError" do
    assert_raise Alembic.TemplateError, fn -> Alembic.compile!("{{ name") end

    assert_raise Alembic.TemplateError, fn ->
      Alembic.render_file!("nope.html", %{}, roots: [@templates_root])
    end

    assert_raise Alembic.TemplateError, fn ->
      Alembic.render!(Alembic.compile!("{{ x }}"), %{}, strict: true)
    end
  end

  test "strict mode errors propagate correctly through render_string/3" do
    assert {:error, {:evaluator, {:undefined_variable, ["x"]}}} =
             Alembic.render_string("{{ x }}", %{}, strict: true)
  end

  test "strict mode errors propagate correctly through render_file/3" do
    # child.html references page.title; omitting "page" from assigns makes
    # that path undefined.
    assert {:error, {:evaluator, {:undefined_variable, ["page", "title"]}}} =
             Alembic.render_file("child.html", %{}, roots: [@templates_root], strict: true)
  end

  test "an unknown filter error surfaces tagged as an evaluator error" do
    assert {:error, {:evaluator, {:unknown_filter, "nope"}}} =
             Alembic.render_string("{{ x | nope }}", %{"x" => "y"})
  end

  test "no raw exception ever escapes render_string/3 for a malformed template" do
    inputs = [
      "{{ ",
      "{% if %}",
      "{{ x ** y }}",
      "{% for x %}",
      "{% unknown_tag %}"
    ]

    for input <- inputs do
      assert {:error, _reason} = Alembic.render_string(input)
    end
  end
end

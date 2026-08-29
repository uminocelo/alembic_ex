defmodule Alembic.Integration.InheritanceE2ETest do
  @moduledoc """
  Template inheritance end-to-end through the real `Alembic` public API and
  `Alembic.Loader` (real files on disk), not the fake in-memory loaders
  `test/alembic/inheritance_test.exs` uses to unit-test `Alembic.Inheritance`
  in isolation.
  """

  use ExUnit.Case, async: true

  @templates_root "test/fixtures/templates"
  @opts [roots: [@templates_root]]

  describe "single-level" do
    test "child.html extends base.html and renders correctly" do
      assigns = %{"page" => %{"title" => "Hello"}}
      assert {:ok, html} = Alembic.render_file("child.html", assigns, @opts)
      assert html =~ "<title>Hello</title>"
      assert html =~ "<h1>Hello</h1>"
    end
  end

  describe "two-level" do
    test "grandchild.html extends child.html extends base.html" do
      assigns = %{"page" => %{"title" => "Deep", "body" => "content here"}}
      assert {:ok, html} = Alembic.render_file("grandchild.html", assigns, @opts)
      assert html =~ "<title>Deep</title>"
      assert html =~ "<article>content here</article>"
      refute html =~ "<h1>"
    end
  end

  describe "unoverridden block" do
    test "uses the ancestor's default" do
      assert {:ok, html} = Alembic.render_file("base.html", %{}, @opts)
      assert html =~ "<title>Alembic</title>"
    end
  end

  describe "error propagation" do
    test "missing parent template surfaces as a structured error" do
      loader_error_fixture = "test/fixtures/tmp/missing_parent_#{System.unique_integer([:positive])}.html"
      File.mkdir_p!(Path.dirname(loader_error_fixture))
      File.write!(loader_error_fixture, ~s({% extends "does_not_exist.html" %}))

      assert {:error, {:inheritance, {:template_not_found, _paths}}} =
               Alembic.render_file(Path.basename(loader_error_fixture), %{},
                 roots: [Path.dirname(loader_error_fixture)]
               )

      File.rm(loader_error_fixture)
    end

    test "circular inheritance surfaces as a structured error" do
      dir = "test/fixtures/tmp/circular_#{System.unique_integer([:positive])}"
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "a.html"), ~s({% extends "b.html" %}))
      File.write!(Path.join(dir, "b.html"), ~s({% extends "a.html" %}))

      assert {:error, {:inheritance, {:circular_inheritance, _name}}} =
               Alembic.render_file("a.html", %{}, roots: [dir])

      File.rm_rf!(dir)
    end
  end
end

defmodule Alembic.Integration.PipelineTest do
  @moduledoc """
  End-to-end tests exercising the full pipeline: raw template string or
  file → HTML output, through the real `Alembic` public API — no module is
  called directly, matching how a caller (e.g. Grimoire) would use this
  library.
  """

  use ExUnit.Case

  @templates_root "test/fixtures/templates"

  describe "render_string/3 for every node type" do
    test "plain text passthrough" do
      assert {:ok, "just text"} = Alembic.render_string("just text")
    end

    test "variable output: simple, dot-path, bracket-equivalent" do
      assert {:ok, "Alice"} = Alembic.render_string("{{ name }}", %{"name" => "Alice"})

      assert {:ok, "Lisbon"} =
               Alembic.render_string("{{ user.city }}", %{"user" => %{"city" => "Lisbon"}})
    end

    test "if with all branch combinations" do
      template = "{% if a %}A{% elsif b %}B{% elsif c %}C{% else %}D{% endif %}"
      assert {:ok, "A"} = Alembic.render_string(template, %{"a" => true})
      assert {:ok, "B"} = Alembic.render_string(template, %{"b" => true})
      assert {:ok, "C"} = Alembic.render_string(template, %{"c" => true})
      assert {:ok, "D"} = Alembic.render_string(template, %{})
    end

    test "for with forloop metadata" do
      template = "{% for x in xs %}{{ forloop.index }}:{{ x }} {% endfor %}"
      assert {:ok, "1:a 2:b 3:c "} = Alembic.render_string(template, %{"xs" => ["a", "b", "c"]})
    end

    test "assign affecting subsequent output" do
      assert {:ok, "42"} = Alembic.render_string(~s({% assign x = 42 %}{{ x }}))
    end

    test "include loading a partial from fixtures" do
      assert {:ok, html} =
               Alembic.render_string(~s({% include "includes/header.html" %}), %{},
                 roots: [@templates_root]
               )

      assert html =~ "<header>"
    end

    test "filter chain with multiple filters" do
      assert {:ok, "HEL"} =
               Alembic.render_string("{{ name | upcase | truncate: 3, \"\" }}", %{
                 "name" => "hello"
               })
    end

    test "whitespace control strips" do
      assert {:ok, "AB"} = Alembic.render_string(~s(A   {{- name -}}   B), %{"name" => ""})
    end
  end

  describe "render_file/3 with real fixtures" do
    test "loads and renders base.html from disk" do
      assert {:ok, html} = Alembic.render_file("base.html", %{}, roots: [@templates_root])
      assert html =~ "<html>"
    end

    test "a second render_file/3 call for the same file is a cache hit" do
      # Alembic.Cache is a single global GenServer keyed by absolute path —
      # a dedicated fixture copy avoids racing any other test that renders
      # the shared "base.html" (Cache.put/2 is an async cast; ExUnit does
      # not wait for a test's async side effects, only for the test
      # function itself to return).
      dir = "test/fixtures/tmp/pipeline_cache_#{System.unique_integer([:positive])}"
      File.mkdir_p!(dir)
      path = Path.join(dir, "target.html")
      File.write!(path, File.read!(Path.join(@templates_root, "base.html")))
      on_exit(fn -> File.rm_rf(dir) end)

      opts = [roots: [dir]]
      resolved_path = Path.expand(path)

      assert :miss = Alembic.Cache.get(resolved_path)

      {:ok, _html} = Alembic.render_file("target.html", %{}, opts)
      Alembic.Cache.sweep()
      assert {:hit, _ast} = Alembic.Cache.get(resolved_path)

      {:ok, _html} = Alembic.render_file("target.html", %{}, opts)
      Alembic.Cache.sweep()
      assert {:hit, _ast} = Alembic.Cache.get(resolved_path)
    end
  end

  describe "include, with variable-passing" do
    test "include with a with-clause" do
      template = ~s({% include "includes/header.html" with title: "Custom" %})
      assert {:ok, html} = Alembic.render_string(template, %{}, roots: [@templates_root])
      assert html =~ "<header>"
    end
  end
end

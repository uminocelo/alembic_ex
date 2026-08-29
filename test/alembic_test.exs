defmodule AlembicTest do
  use ExUnit.Case

  doctest Alembic

  @templates_root "test/fixtures/templates"

  describe "compile/2 and render/3 round-trip" do
    test "compile then render" do
      {:ok, ast} = Alembic.compile("Hello {{ name }}!")
      assert {:ok, "Hello World!"} = Alembic.render(ast, %{"name" => "World"})
    end

    test "compile surfaces a lexer error" do
      assert {:error, {:lexer, {:unterminated_output, %{line: 1, col: 1}}}} =
               Alembic.compile("{{ name")
    end

    test "compile surfaces a parser error" do
      assert {:error, {:parser, {:missing_end_tag, "endif"}}} =
               Alembic.compile("{% if x %}no close")
    end
  end

  describe "render_string/3" do
    test "convenience compile + render in one call" do
      assert {:ok, "Hi Alice"} = Alembic.render_string("Hi {{ user }}", %{"user" => "Alice"})
    end

    test "full node coverage: if, for, assign, filter chain" do
      template = """
      {% assign greeting = "Hi" %}\
      {% if user.admin %}{{ greeting }}, admin {{ user.name | upcase }}!{% else %}{{ greeting }}, {{ user.name }}.{% endif %}\
      {% for tag in tags %} tag:{{ tag }}{% endfor %}\
      """

      assigns = %{"user" => %{"admin" => true, "name" => "alice"}, "tags" => ["a", "b"]}
      assert {:ok, "Hi, admin ALICE! tag:a tag:b"} = Alembic.render_string(template, assigns)
    end
  end

  describe "render_file/3" do
    test "loads, compiles, and renders a real file from disk" do
      assert {:ok, html} =
               Alembic.render_file("base.html", %{}, roots: [@templates_root])

      assert html =~ "Alembic"
    end

    test "the second call for the same file is a cache hit" do
      {dir, path} = unique_fixture_copy!()
      opts = [roots: [dir]]

      {:ok, _html} = Alembic.render_file("cache_target.html", %{}, opts)
      # Cache.put/2 is an async cast; force it to have been processed
      # before the synchronous ETS read below.
      Alembic.Cache.sweep()

      assert {:hit, _ast} = Alembic.Cache.get(path)
    end

    test "cache: false bypasses the cache for that call" do
      {dir, path} = unique_fixture_copy!()
      opts = [roots: [dir], cache: false]

      {:ok, _html} = Alembic.render_file("cache_target.html", %{}, opts)
      Alembic.Cache.sweep()
      assert :miss = Alembic.Cache.get(path)
    end

    test "a missing file surfaces a loader error" do
      assert {:error, {:loader, {:template_not_found, _paths}}} =
               Alembic.render_file("missing.html", %{}, roots: [@templates_root])
    end

    test "template inheritance resolves through the loader" do
      assigns = %{"page" => %{"title" => "My Post"}}

      assert {:ok, html} = Alembic.render_file("child.html", assigns, roots: [@templates_root])
      assert html =~ "<title>My Post</title>"
      assert html =~ "<h1>My Post</h1>"
    end
  end

  describe "bang variants" do
    test "compile! raises Alembic.TemplateError on error" do
      assert_raise Alembic.TemplateError, fn ->
        Alembic.compile!("{% if unclosed")
      end
    end

    test "compile! returns the AST on success" do
      assert [{:text, "hi"}] = Alembic.compile!("hi")
    end

    test "render! raises Alembic.TemplateError on error" do
      ast = Alembic.compile!("{{ x }}")

      assert_raise Alembic.TemplateError, fn ->
        Alembic.render!(ast, %{}, strict: true)
      end
    end

    test "render_string! returns the rendered output on success" do
      assert "Hi Alice" = Alembic.render_string!("Hi {{ user }}", %{"user" => "Alice"})
    end

    test "render_string! raises Alembic.TemplateError on error" do
      assert_raise Alembic.TemplateError, fn ->
        Alembic.render_string!("{{ x }}", %{}, strict: true)
      end
    end

    test "render_file! raises Alembic.TemplateError for a missing file" do
      assert_raise Alembic.TemplateError, fn ->
        Alembic.render_file!("missing.html", %{}, roots: [@templates_root])
      end
    end
  end

  describe "strict mode" do
    test "strict: true errors on an undefined variable" do
      assert {:error, {:evaluator, {:undefined_variable, ["missing"]}}} =
               Alembic.render_string("{{ missing }}", %{}, strict: true)
    end

    test "lenient mode (default) renders an undefined variable as empty string" do
      assert {:ok, ""} = Alembic.render_string("{{ missing }}", %{})
    end
  end

  describe "Alembic.CompileError and Alembic.RenderError (available, not raised by the bang API)" do
    test "CompileError formats a message including the reason and a template excerpt" do
      error = %Alembic.CompileError{reason: {:lexer, :some_reason}, template: "{{ broken"}
      assert Exception.message(error) =~ "Alembic compile error"
      assert Exception.message(error) =~ "some_reason"
      assert Exception.message(error) =~ "{{ broken"
    end

    test "CompileError formats a message with no template excerpt when template is nil" do
      error = %Alembic.CompileError{reason: :whatever, template: nil}
      assert Exception.message(error) == "Alembic compile error: :whatever"
    end

    test "RenderError formats a message including the reason and a context excerpt" do
      error = %Alembic.RenderError{reason: {:evaluator, :boom}, context: %{"a" => 1}}
      assert Exception.message(error) =~ "Alembic render error"
      assert Exception.message(error) =~ "boom"
      assert Exception.message(error) =~ "a"
    end

    test "RenderError formats a message with no context excerpt when context is nil" do
      error = %Alembic.RenderError{reason: :whatever, context: nil}
      assert Exception.message(error) == "Alembic render error: :whatever"
    end
  end

  # Alembic.Cache is a single global GenServer keyed by absolute path — two
  # tests (in this file or another) that both render "base.html" from the
  # shared fixtures root would race on the same cache entry. Each test that
  # cares about cache state gets its own directory and file instead.
  defp unique_fixture_copy! do
    dir = "test/fixtures/tmp/alembic_test_#{System.unique_integer([:positive])}"
    File.mkdir_p!(dir)
    path = Path.join(dir, "cache_target.html")
    File.write!(path, File.read!(Path.join(@templates_root, "base.html")))
    on_exit(fn -> File.rm_rf(dir) end)
    {dir, Path.expand(path)}
  end
end

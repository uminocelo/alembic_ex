defmodule Alembic.LoaderTest do
  use ExUnit.Case, async: true

  doctest Alembic.Loader

  alias Alembic.Loader

  @templates_root "test/fixtures/templates"

  describe "load/2" do
    test "happy path: reads a template from a single root" do
      assert {:ok, content} = Loader.load("base.html", roots: [@templates_root])
      assert content =~ "Alembic"
    end

    test "not found includes all searched paths in the error" do
      assert {:error, {:template_not_found, paths}} =
               Loader.load("missing.html", roots: [@templates_root])

      assert Enum.any?(paths, &String.ends_with?(&1, "missing.html"))
    end

    test "multi-root fallthrough: second root used when the first doesn't have the file" do
      assert {:ok, content} =
               Loader.load("shared.html", roots: ["test/fixtures/site", "test/fixtures/shared"])

      assert content =~ "from shared root"
    end

    test "extension auto-append when the template name has none" do
      assert {:ok, _content} =
               Loader.load("base", roots: [@templates_root], extensions: [".html"])
    end

    test "a name with an explicit extension is used as-is, without appending more" do
      assert {:ok, _content} = Loader.load("base.html", roots: [@templates_root], extensions: [".liquid"])
    end

    test "path traversal attempt returns a structured error and never reads the file" do
      assert {:error, {:path_traversal_detected, _path}} =
               Loader.load("../../../../../../etc/passwd", roots: [@templates_root])
    end

    test "a name starting with a leading slash cannot escape the root either" do
      # Path.join/2 never lets its second argument become absolute, so this
      # resolves to `<root>/etc/passwd.*` — still inside the root, just not
      # found — rather than a traversal outside it.
      assert {:error, {:template_not_found, paths}} = Loader.load("/etc/passwd", roots: [@templates_root])
      assert Enum.all?(paths, &String.starts_with?(&1, Path.expand(@templates_root)))
    end

    test "reads application config when no :roots opt is given" do
      Application.put_env(:alembic, :template_roots, [@templates_root])
      assert {:ok, _content} = Loader.load("base.html")
    after
      Application.delete_env(:alembic, :template_roots)
    end

    test "per-call opts override application config" do
      Application.put_env(:alembic, :template_roots, ["test/fixtures/nonexistent"])
      assert {:ok, _content} = Loader.load("base.html", roots: [@templates_root])
    after
      Application.delete_env(:alembic, :template_roots)
    end
  end

  describe "resolve_path/2" do
    test "returns the absolute path without reading content" do
      assert {:ok, path} = Loader.resolve_path("base.html", roots: [@templates_root])
      assert String.ends_with?(path, "/test/fixtures/templates/base.html")
      assert Path.type(path) == :absolute
    end

    test "not found includes all searched paths" do
      assert {:error, {:template_not_found, paths}} =
               Loader.resolve_path("missing.html", roots: [@templates_root])

      assert Enum.any?(paths, &String.ends_with?(&1, "missing.html"))
    end

    test "still protects against path traversal" do
      assert {:error, {:path_traversal_detected, _path}} =
               Loader.resolve_path("../../../../../../etc/passwd", roots: [@templates_root])
    end
  end

  describe "build_loader/1" do
    test "returns a function suitable for injection into Inheritance.resolve_chain/3" do
      loader = Loader.build_loader(roots: [@templates_root])
      assert is_function(loader, 1)
      assert {:ok, _content} = loader.("base.html")
    end

    test "the returned function still reports not-found errors" do
      loader = Loader.build_loader(roots: [@templates_root])
      assert {:error, {:template_not_found, _}} = loader.("nope.html")
    end
  end

  describe "stat/2" do
    test "returns the mtime of a resolved template" do
      assert {:ok, %DateTime{}} = Loader.stat("base.html", roots: [@templates_root])
    end

    test "returns a template_not_found error for a missing template" do
      assert {:error, {:template_not_found, _paths}} = Loader.stat("missing.html", roots: [@templates_root])
    end
  end
end

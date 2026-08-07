defmodule AlembicTest do
  use ExUnit.Case

  alias Alembic.TestFixtures

  describe "compile/2" do
    test "returns a tagged error while the compiler is not implemented" do
      source = TestFixtures.plain_template()
      assert Alembic.compile(source, []) == {:error, :not_implemented}
    end
  end

  describe "render/3" do
    test "returns a tagged error while the renderer is not implemented" do
      assigns = TestFixtures.empty_assigns()
      assert Alembic.render(:compiled_template, assigns, []) == {:error, :not_implemented}
    end
  end

  describe "render_file/3" do
    test "returns a tagged error while file rendering is not implemented" do
      assigns = TestFixtures.empty_assigns()
      assert Alembic.render_file("template.alembic", assigns, []) == {:error, :not_implemented}
    end
  end

  describe "compile!/2" do
    test "raises when compilation fails" do
      source = TestFixtures.plain_template()

      assert_raise RuntimeError, "Alembic compile failed: :not_implemented", fn ->
        Alembic.compile!(source, [])
      end
    end
  end

  describe "render!/3" do
    test "raises when rendering fails" do
      assigns = TestFixtures.empty_assigns()

      assert_raise RuntimeError, "Alembic render failed: :not_implemented", fn ->
        Alembic.render!(:compiled_template, assigns, [])
      end
    end
  end
end

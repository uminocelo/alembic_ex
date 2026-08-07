defmodule Alembic.ASTTest do
  use ExUnit.Case, async: true

  alias Alembic.ASTFixtures

  describe "leaf node" do
    test "represents plain text" do
      node = {:text, "Hello"}

      assert {:text, content} = node
      assert content == "Hello"
    end

    test "represents output paths and filters" do
      node = ASTFixtures.output_node()

      assert {:output, path, filters} = node
      assert path == ["user", "name"]
      assert filters == [{:filter, "upcase", []}]
    end
  end

  describe "control-flow nodes" do
    test "every position of an if node" do
      node = ASTFixtures.if_node()

      assert {:if, condition, then_branch, elsif_branch, else_branch} = node
      assert condition == {:variable, ["user", "name"]}
      assert then_branch == [{:text, "Administrator"}]
      assert elsif_branch == [{{:variable, ["user", "editor"]}, [:text, "Editor"]}]
      assert else_branch == [{:text, "Member"}]
    end

    test "every position of a for node" do
      node = ASTFixtures.for_node()

      assert {:for, variable, iterable, body, else_branch} = node
      assert variable == "post"
      assert iterable == {:variable, ["posts"]}
      assert body == [{:output, ["post", "title"], []}]
      assert else_branch == [{:text, "No posts found"}]
    end

    test "allows nil else branch" do
      if_node = {:if, {:variable, ["user", "name"]}, [{:text, "Admininstrator"}], [], nil}
      for_node = {:for, "post", {:variable, ["posts"]}, [{:output, ["posts", "title"], []}], nil}
      assert {:if, _, _, [], nil} = if_node
      assert {:for, _, _, _, nil} = for_node
    end
  end

  describe "assignment nodes" do
    test "variable name and assignment expression" do
      node = {:assign, "title", {:literal, "Welcome"}}
      assert {:assign, variable, expression} = node
      assert variable == "title"
      assert expression == {:literal, "Welcome"}
    end
  end

  describe "template composition nodes" do
    test "template inheritance" do
      node = {:extends, "base.html"}
      assert {:extends, "base.html"} = node
    end

    test "named blocks with nested nodes" do
      node = {:block, "content", [{:text, "Hello, "}, {:output, ["user", "name"], []}]}

      assert {:block, "content", body} = node
      assert body == [{:text, "Hello, "}, {:output, ["user", "name"], []}]
    end

    test "includes  with variable" do
      node = {:include, "header.html", %{"title" => {:literal, "Welcome"}}}

      assert {:include, template_name, variables} = node
      assert template_name == "header.html"
      assert variables == %{"title" => {:literal, "Welcome"}}
    end
  end

  describe "nested ASTs" do
    ast = ASTFixtures.non_trivial_ast()

    assert [
             {:extends, "base.html"},
             {:assign, "heading", {:literal, "Posts"}},
             {:block, "content", block_body}
           ] = ast

    assert [
             {:text, "Hello, "},
             {:output, ["user", "name"], [{:filter, "upcase", []}]},
             {:if, _, _, _, _},
             {:for, _, _, _, _},
             {:include, "footer.html", %{}}
           ] = block_body
  end
end

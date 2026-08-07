defmodule Alembic.ASTFixtures do
  @moduledoc false

  alias Alembic.AST

  @spec output_node() :: AST.output_node()
  def output_node do
    {:output, ["user", "name"], [{:filter, "upcase", []}]}
  end

  @spec if_node() :: AST.if_node()
  def if_node do
    {
      :if,
      {:variable, ["user", "name"]},
      [
        {:text, "Administrator"}
      ],
      [
        {
          {:variable, ["user", "editor"]},
          [:text, "Editor"]
        }
      ],
      [{:text, "Member"}]
    }
  end

  @spec for_node() :: AST.for_node()
  def for_node do
    {:for, "post", {:variable, ["posts"]}, [{:output, ["post", "title"], []}],
     [{:text, "No posts found"}]}
  end

  def non_trivial_ast do
    [
      {:extends, "base.html"},
      {:assign, "heading", {:literal, "Posts"}},
      {:block, "content",
       [
         {:text, "Hello, "},
         output_node(),
         if_node(),
         for_node(),
         {:include, "footer.html", %{}}
       ]}
    ]
  end
end

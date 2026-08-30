
# Run with: mix run examples/05_inheritance/run.exs
#
# Template inheritance: {% extends %} / {% block %} / {% endblock %}.
#
# templates/base.html defines "title", "content", and "footer" blocks.
# templates/post.html extends it, overriding "title" and "content" but
# leaving "footer" at its default. templates/legal.html overrides "footer"
# using {{ block.super }} to prepend to the parent's default content.

root = Path.join(__DIR__, "templates")

{:ok, post_html} =
  Alembic.render_file("post.html", %{"post" => %{"title" => "Hello, Alembic", "body" => "First post!"}},
    roots: [root]
  )

IO.puts(post_html)
IO.puts(String.duplicate("-", 40))

{:ok, legal_html} = Alembic.render_file("legal.html", %{}, roots: [root])
IO.puts(legal_html)

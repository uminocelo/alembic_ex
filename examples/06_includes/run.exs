
# Run with: mix run examples/06_includes/run.exs
#
# {% include %} loads and renders a partial. Unlike an isolated "render"
# tag, Alembic's {% include %} shares the including template's scope:
# - header.html's `site_title` comes from an explicit `with` clause.
# - footer.html's `site_title` and `year` come from the *caller's* own
#   scope, with no `with` clause needed at all.

root = Path.join(__DIR__, "templates")

assigns = %{
  "body" => "Welcome to the site!",
  "site_title" => "My Site",
  "year" => 2026
}

{:ok, html} = Alembic.render_file("page.html", assigns, roots: [root])
IO.puts(html)

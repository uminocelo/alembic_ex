
# Run with: mix run examples/08_error_handling.exs
#
# Every non-bang Alembic function returns {:ok, value} | {:error, reason}.
# Errors are tagged by which pipeline stage produced them, so you can
# pattern-match on the stage without inspecting the whole reason.

IO.puts("--- Lexer error (unterminated tag) ---")
IO.inspect(Alembic.render_string("Hello {{ name"))
# => {:error, {:lexer, {:unterminated_output, %{line: 1, col: 7}}}}

IO.puts("\n--- Parser error (missing endif) ---")
IO.inspect(Alembic.render_string("{% if user.admin %}admin only"))
# => {:error, {:parser, {:missing_end_tag, "endif", %{line: 1, col: 1}}}}
# The position points at the {% if %} that's missing its close, not at
# end-of-input — that's the only useful place to point when the closing
# tag simply doesn't exist anywhere in the template.

IO.puts("\n--- Loader error (file not found) ---")
IO.inspect(Alembic.render_file("does_not_exist.html", %{}, roots: ["/tmp"]))
# => {:error, {:loader, {:template_not_found, [...]}}}

IO.puts("\n--- Evaluator error (unknown filter) ---")
IO.inspect(Alembic.render_string("{{ name | frobnicate }}", %{"name" => "x"}))
# => {:error, {:evaluator, {:unknown_filter, "frobnicate"}}}

IO.puts("\n--- strict: true — undefined variables become errors ---")
IO.inspect(Alembic.render_string("{{ typo_prone_field }}", %{}))
IO.inspect(Alembic.render_string("{{ typo_prone_field }}", %{}, strict: true))
# => {:ok, ""}                                            (lenient, default)
# => {:error, {:evaluator, {:undefined_variable, [...]}}} (strict)

IO.puts("\n--- Bang variants raise Alembic.TemplateError ---")

try do
  Alembic.render_string!("{{ name | frobnicate }}", %{"name" => "x"})
rescue
  e in Alembic.TemplateError -> IO.puts("Rescued: #{Exception.message(e)}")
end

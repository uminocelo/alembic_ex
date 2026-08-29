
# Run with: mix run examples/01_hello_world.exs
#
# The simplest possible use of Alembic: compile a template string and
# render it against an assigns map, in one call.

{:ok, output} = Alembic.render_string("Hello, {{ name }}!", %{"name" => "World"})
IO.puts(output)
# => Hello, World!

# Variable paths use dot notation to reach into nested maps.
{:ok, output} =
  Alembic.render_string("{{ user.address.city }}", %{
    "user" => %{"address" => %{"city" => "Lisbon"}}
  })

IO.puts(output)
# => Lisbon

# An undefined variable renders as an empty string by default (lenient
# mode) rather than raising or erroring.
{:ok, output} = Alembic.render_string("Value: [{{ missing }}]", %{})
IO.puts(output)
# => Value: []

# compile/2 and render/3 are separate steps — compile once, render many
# times with different assigns, without re-parsing the template.
{:ok, ast} = Alembic.compile("{{ greeting }}, {{ name }}!")
{:ok, output1} = Alembic.render(ast, %{"greeting" => "Hi", "name" => "Alice"})
{:ok, output2} = Alembic.render(ast, %{"greeting" => "Hey", "name" => "Bob"})
IO.puts(output1)
# => Hi, Alice!
IO.puts(output2)
# => Hey, Bob!

# Bang (!) variants return the value directly and raise on error instead
# of returning {:ok, _} / {:error, _}.
output = Alembic.render_string!("Bang variant: {{ x }}", %{"x" => 42})
IO.puts(output)
# => Bang variant: 42

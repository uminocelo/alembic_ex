# Run with: mix run examples/09_loop_control.exs
#
# Loop control inside {% for %}: {% break %} / {% continue %}, the
# {% cycle %} tag, and inline `(from..to)` range iterables.

# {% break %} stops the loop immediately; {% continue %} skips only the rest
# of the current iteration. Both are parse errors outside a {% for %} body.
items = %{"items" => [1, 2, 3, 4, 5]}

{:ok, output} =
  Alembic.render_string(
    "{% for n in items %}{% if n == 4 %}{% break %}{% endif %}{{ n }} {% endfor %}",
    items
  )

IO.puts("break at 4:   #{String.trim_trailing(output)}")
# => break at 4:   1 2 3

{:ok, output} =
  Alembic.render_string(
    "{% for n in items %}{% if n == 3 %}{% continue %}{% endif %}{{ n }} {% endfor %}",
    items
  )

IO.puts("skip 3:       #{String.trim_trailing(output)}")
# => skip 3:       1 2 4 5

# In nested loops, a break exits only the innermost loop.
nested = """
{% for row in rows %}{% for cell in cols %}{% if cell == 2 %}{% break %}{% endif %}{{ row }}{{ cell }}{% endfor %}{% endfor %}\
"""

{:ok, output} =
  Alembic.render_string(nested, %{"rows" => ["a", "b"], "cols" => [1, 2, 3]})

IO.puts("nested break: #{output}")
# => nested break: a1b1

# {% cycle %} advances through its values on each call and wraps. It's the
# usual tool for zebra-striping a list.
{:ok, output} =
  Alembic.render_string(
    "{% for n in items %}{% cycle \"odd\", \"even\" %} {% endfor %}",
    items
  )

IO.puts("cycle:        #{String.trim_trailing(output)}")
# => cycle:        odd even odd even odd

# A named group ({% cycle "name": ... %}) shares one counter across every
# call with that name — even across separate loops.
named = """
{% for n in first %}{% cycle "row": "light", "dark" %}-{% endfor %} {% for n in second %}{% cycle "row": "light", "dark" %}-{% endfor %}\
"""

{:ok, output} = Alembic.render_string(named, %{"first" => [1, 2], "second" => [3, 4]})

IO.puts("named cycle:  #{String.trim_trailing(output)}")
# => named cycle:  light-dark- light-dark-

# Ranges iterate inclusively and accept integer literals or variables.
{:ok, output} = Alembic.render_string("{% for i in (1..5) %}{{ i }} {% endfor %}", %{})
IO.puts("range:        #{String.trim_trailing(output)}")
# => range:        1 2 3 4 5

{:ok, output} =
  Alembic.render_string("{% for i in (start..stop) %}{{ i }} {% endfor %}", %{
    "start" => 2,
    "stop" => 4
  })

IO.puts("var range:    #{String.trim_trailing(output)}")
# => var range:    2 3 4

# A descending range iterates zero times and falls through to {% else %} —
# Liquid parity, not Elixir's descending-range behavior.
{:ok, output} =
  Alembic.render_string("{% for i in (5..1) %}{{ i }}{% else %}nothing to show{% endfor %}", %{})

IO.puts("descending:   #{output}")
# => descending:   nothing to show

# The parser rejects loop-control tags outside a loop, and a range with a
# non-integer endpoint fails at render time.
{:error, {:parser, {:break_outside_loop, %{line: 1, col: 1}}}} =
  Alembic.render_string("{% break %}", %{})

IO.puts("outside loop: rejected")
# => outside loop: rejected

{:error, {:evaluator, {:range_non_integer, 1, "nope"}}} =
  Alembic.render_string("{% for i in (1..stop) %}{{ i }}{% endfor %}", %{"stop" => "nope"})

IO.puts("bad range:    rejected")
# => bad range:    rejected

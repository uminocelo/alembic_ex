defmodule Alembic.AST do
  @moduledoc false

  @type path :: [String.t()]
  @type literal :: String.t() | number() | boolean() | nil
  @type compare_op :: :eq | :neq | :gt | :lt | :gte | :lte | :contains
  @type logical_op :: :and | :or
  @type expr ::
          {:variable, path()}
          | {:literal, literal()}
          | {:filter_chain, expr(), [filter()]}
          | {:compare, compare_op(), expr(), expr()}
          | {:logical, logical_op(), expr(), expr()}
          | {:not, expr()}
  @type filter :: {:filter, String.t(), [expr()]}
  @type text_node :: {:text, String.t()}
  @type output_node :: {:output, path(), [filter()]}
  @type if_node :: {:if, expr(), [ast_node()], [{expr(), [ast_node()]}], [ast_node()] | nil}
  @type for_node :: {:for, String.t(), expr(), [ast_node()], [ast_node()] | nil}
  @type assign_node :: {:assign, String.t(), expr()}
  @type extends_node :: {:extends, String.t()}
  @type block_node :: {:block, String.t(), [ast_node()]}
  @type include_node :: {:include, String.t(), map()}
  @type ast_node ::
          text_node()
          | output_node()
          | if_node()
          | for_node()
          | assign_node()
          | extends_node()
          | block_node()
          | include_node()
  @type t :: [ast_node()]
end

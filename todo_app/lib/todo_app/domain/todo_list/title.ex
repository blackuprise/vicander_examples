defmodule TodoApp.Domain.TodoList.Title do
  @moduledoc "Value object: the text of a todo item (at most 100 characters)."
  use DDD.ValueObject

  value_object do
    field :value, :string, required: true

    invariant TodoApp.Domain.TodoList.Specs.TitleWithinLimit, on: :value, max: 100
  end
end

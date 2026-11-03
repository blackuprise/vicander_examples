defmodule TodoApp.Domain.TodoList.Specs.ItemSatisfies do
  @moduledoc """
  Lifts a rule about an *item* into a rule about the *list that holds it*.

      requires: [ItemExists, {ItemSatisfies, spec: ItemNotCompleted}]

  It finds the item the operation is about (the first argument after the list) and applies the
  item-level `:spec` to it. The rule stays written once, on the item, and the list's operation
  states it where a reader looks. If the item doesn't exist it says nothing: `ItemExists`
  already reports that.
  """
  use DDD.Specification, field: :items

  @impl DDD.Specification
  def check(%{items: items}, opts) do
    spec = Keyword.fetch!(opts, :spec)
    [item_id | _] = Keyword.fetch!(opts, :args)

    with %{} = item <- Enum.find(items, &(&1.id == item_id)),
         {:error, violation} <- DDD.Specification.evaluate(spec, item) do
      {:error, violation.code, violation.message, violation.details}
    else
      _satisfied_or_missing -> :ok
    end
  end
end

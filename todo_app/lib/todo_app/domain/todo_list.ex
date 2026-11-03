defmodule TodoApp.Domain.TodoList do
  @moduledoc """
  Aggregate root: a user's todo list and the items inside it.

  The whole aggregate is saved as one row. All changes go through its operations, which
  re-check every invariant and emit events only when the result is valid.
  """
  use DDD.Aggregate

  alias TodoApp.Domain.TodoList.{Events, Specs, TodoItem}

  aggregate do
    description "A user's todo list with its items"

    identity :id, :uuid

    field :owner_id, {:ref, TodoApp.Domain.User},
      required: true,
      description: "The id of the user who owns the list"

    field :name, :string, required: true, description: "The name of the list"
    field :items, {:list, TodoItem}, default: [], description: "The items, oldest first"

    invariant TodoApp.Domain.TodoList.Specs.ListNameNotBlank, on: :name
    invariant TodoApp.Domain.TodoList.Specs.MaxOpenItems, max: 10
  end

  # Each operation states its prerequisites as named specifications (`requires:`), checked
  # before the body runs. They are evaluated against the list, and see the operation's other
  # arguments, so "the item exists" and "the item is not completed" are rules of the list's
  # operation. A rule about one item is written once, on the item, and lifted to the list with
  # `ItemSatisfies` (a spec for items placed directly here would find no `status` on the list
  # and pass every call). The item's own operations still enforce their rules as well.

  defop add_item(list, item) do
    list
    |> Map.put(:items, list.items ++ [item])
    |> emit_event(Events.ItemAdded.new(%{item_id: item.id, title: item.title.value}))
  end

  defop complete_item(list, item_id),
    requires: [Specs.ItemExists, {Specs.ItemSatisfies, spec: Specs.ItemNotCompleted}] do
    with {:ok, done} <- list |> find_item(item_id) |> TodoItem.complete() do
      list
      |> replace_item(done)
      |> emit_event(Events.ItemCompleted.new(%{item_id: item_id}))
    end
  end

  defop rename_item(list, item_id, title),
    requires: [Specs.ItemExists, {Specs.ItemSatisfies, spec: Specs.ItemEditable}] do
    with {:ok, renamed} <- list |> find_item(item_id) |> TodoItem.rename(title) do
      replace_item(list, renamed)
    end
  end

  # Only called after `ItemExists` has passed.
  defp find_item(list, item_id), do: Enum.find(list.items, &(&1.id == item_id))

  defp replace_item(list, updated) do
    %{list | items: Enum.map(list.items, &if(&1.id == updated.id, do: updated, else: &1))}
  end
end

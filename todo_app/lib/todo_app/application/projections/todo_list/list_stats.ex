defmodule TodoApp.Application.Projections.TodoList.ListStats do
  @moduledoc """
  A read model: one row per todo list with how many items were added and completed, and when it
  last changed. It is fed by the list's events through the outbox, so reading it never loads
  and folds a whole list.

      TodoApp.Application.Projections.TodoList.ListStats.get(list_id)
      TodoApp.Application.Projections.TodoList.ListStats.page(order: [desc: :last_activity_at])

  Eventually consistent: a number here can trail the list by the time the outbox takes to
  deliver. Business rules read the aggregate, never this. After changing an `on` clause run
  `mix vic.projection.rebuild TodoApp.Application.Projections.TodoList.ListStats`.
  """
  alias TodoApp.Domain.TodoList.Events.{ItemAdded, ItemCompleted}

  use DDD.Projection,
    table: "todo_list_stats",
    key: :list_id,
    events: [ItemAdded, ItemCompleted]

  projection do
    description "Per todo list: items added, items completed and the time of the last change"
    field :list_id, :uuid
    field :items_added, :integer, default: 0
    field :items_completed, :integer, default: 0
    field :last_activity_at, :datetime_usec
  end

  on %ItemAdded{} = event,
    do: [{:inc, :items_added, 1}, {:update, %{last_activity_at: event.occurred_at}}]

  on %ItemCompleted{} = event,
    do: [{:inc, :items_completed, 1}, {:update, %{last_activity_at: event.occurred_at}}]
end

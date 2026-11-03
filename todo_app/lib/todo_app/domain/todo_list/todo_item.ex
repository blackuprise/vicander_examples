defmodule TodoApp.Domain.TodoList.TodoItem do
  @moduledoc """
  Entity inside a `TodoApp.Domain.TodoList`.

  The status is an enum (`:open` or `:done`) and the priority one of `:low`, `:normal` and
  `:high`, both checked by their type. Tags are a list of strings. Invariant specs keep it valid
  (title not blank, no past due date on open items, at most 5 short tags). The operations state
  their business rules as named preconditions: a completed item cannot be
  completed again (`:already_completed`) or edited (`:item_completed`). Breaking one returns a
  `:precondition_failed` business error with that code in its violations.
  """
  use DDD.Entity

  entity do
    identity :id, :uuid
    field :title, {:one, TodoApp.Domain.TodoList.Title}, required: true
    field :status, {:enum, [:open, :done]}, default: :open
    field :priority, {:enum, [:low, :normal, :high]}, default: :normal
    field :tags, {:array, :string}, default: []
    field :due_date, :date
    field :completed_at, :datetime

    invariant TodoApp.Domain.TodoList.Specs.TagsWithinLimit, on: :tags
    invariant TodoApp.Domain.TodoList.Specs.TitleNotBlank
    invariant TodoApp.Domain.TodoList.Specs.DueDateNotPast
  end

  # The business rules are named preconditions (`requires:`). The patterns only describe the
  # shape of the arguments.
  defop rename(item, %TodoApp.Domain.TodoList.Title{} = title),
    requires: TodoApp.Domain.TodoList.Specs.ItemEditable do
    %{item | title: title}
  end

  defop reschedule(item, %Date{} = due_date),
    requires: TodoApp.Domain.TodoList.Specs.ItemEditable do
    %{item | due_date: due_date}
  end

  defop complete(item), requires: TodoApp.Domain.TodoList.Specs.ItemNotCompleted do
    %{item | status: :done, completed_at: DateTime.utc_now()}
  end
end

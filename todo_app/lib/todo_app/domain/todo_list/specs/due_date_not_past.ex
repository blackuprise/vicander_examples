defmodule TodoApp.Domain.TodoList.Specs.DueDateNotPast do
  @moduledoc """
  An open item's due date cannot be in the past.

  Done items are exempt, so an overdue item can still be completed. An overdue open
  item has to be rescheduled before it can be changed in any other way.
  """
  use DDD.Specification, field: :due_date

  @impl DDD.Specification
  def check(%{status: :open, due_date: %Date{} = due_date}, _opts) do
    if Date.compare(due_date, Date.utc_today()) == :lt,
      do: {:error, :due_date_in_past, "due date cannot be in the past", %{due_date: due_date}},
      else: :ok
  end

  def check(_entity, _opts), do: :ok
end

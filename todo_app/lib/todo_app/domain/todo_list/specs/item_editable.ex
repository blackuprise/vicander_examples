defmodule TodoApp.Domain.TodoList.Specs.ItemEditable do
  @moduledoc """
  Precondition of changing an item (rename, reschedule): a completed item is frozen.
  """
  use DDD.Specification, field: :status

  @impl DDD.Specification
  def check(%{status: :done, completed_at: completed_at}, _opts),
    do:
      {:error, :item_completed, "a completed item cannot be edited",
       %{status: :done, completed_at: completed_at}}

  def check(_entity, _opts), do: :ok
end

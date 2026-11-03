defmodule TodoApp.Domain.TodoList.Specs.ItemNotCompleted do
  @moduledoc """
  Precondition of completing an item: it has not been completed already.
  """
  use DDD.Specification, field: :status

  @impl DDD.Specification
  def check(%{status: :done, completed_at: completed_at}, _opts),
    do:
      {:error, :already_completed, "item is already completed",
       %{status: :done, completed_at: completed_at}}

  def check(_entity, _opts), do: :ok
end

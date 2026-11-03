defmodule TodoApp.Domain.User.Specs.CompletedTasksAtLeast do
  @moduledoc "The user has completed at least `:min` tasks. Reusable by every progress tier."
  use DDD.Specification, field: :completed_tasks

  @impl DDD.Specification
  def check(%{completed_tasks: completed}, opts) do
    min = Keyword.fetch!(opts, :min)

    if completed >= min,
      do: :ok,
      else:
        {:error, :not_enough_completed_tasks, "needs #{min} completed tasks, has #{completed}",
         %{min: min, completed: completed}}
  end
end

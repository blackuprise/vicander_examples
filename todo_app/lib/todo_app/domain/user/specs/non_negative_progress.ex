defmodule TodoApp.Domain.User.Specs.NonNegativeProgress do
  @moduledoc "A count of completed tasks cannot be negative. A value spec (`on: :completed_tasks`)."
  use DDD.Specification, scope: :value

  @impl DDD.Specification
  def check(completed, _opts) when is_integer(completed) and completed < 0,
    do: {:error, :negative_progress, "cannot be negative", %{completed_tasks: completed}}

  def check(_completed, _opts), do: :ok
end

defmodule TodoApp.Domain.User.Achievements do
  @moduledoc """
  The achievement catalog. Each achievement is a code, a description and a specification
  over the user: it is earned when the specification is satisfied.

    * `:newbie`     - completed the first task
    * `:beginner`   - completed 10 tasks
    * `:performer`  - completed 30 tasks

  Adding an achievement means adding a line here.
  """

  alias TodoApp.Domain.User.Specs.CompletedTasksAtLeast

  @catalog [
    newbie: %{
      title: "Newbie",
      description: "Completed your first task",
      spec: {CompletedTasksAtLeast, min: 1}
    },
    beginner: %{
      title: "Beginner",
      description: "Completed 10 tasks",
      spec: {CompletedTasksAtLeast, min: 10}
    },
    performer: %{
      title: "Performer",
      description: "Completed 30 tasks",
      spec: {CompletedTasksAtLeast, min: 30}
    }
  ]

  @doc "All achievement codes, in catalog order."
  def codes, do: Keyword.keys(@catalog)

  @doc "The catalog entry (`title`, `description`, `spec`) for a code, or nil."
  def get(code), do: Keyword.get(@catalog, code)

  @doc "Codes whose specification the user satisfies, in catalog order."
  def earned_by(user) do
    for {code, %{spec: spec}} <- @catalog, DDD.Specification.evaluate(spec, user) == :ok, do: code
  end
end

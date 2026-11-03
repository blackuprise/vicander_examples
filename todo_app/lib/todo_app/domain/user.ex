defmodule TodoApp.Domain.User do
  @moduledoc """
  Aggregate: a person who owns todo lists. Lists refer to it by id only.

  Tracks progress (`completed_tasks`) and the achievements earned from it. Which
  achievements exist is defined by `TodoApp.Domain.User.Achievements`; the invariants guarantee a user
  never holds one twice or one they did not earn.
  """
  use DDD.Aggregate

  alias TodoApp.Domain.User.{Achievement, Achievements, Events}

  aggregate do
    description "A person who owns todo lists, with their progress and achievements"

    identity :id, :uuid
    field :name, :string, required: true, description: "The user's name"
    field :email, :string, required: true, description: "The user's email address"
    field :completed_tasks, :integer, default: 0, description: "Tasks completed across all lists"
    field :achievements, {:list, Achievement}, default: [], description: "Achievements earned"

    invariant TodoApp.Domain.User.Specs.ValidEmail, on: :email
    invariant TodoApp.Domain.User.Specs.NonNegativeProgress, on: :completed_tasks
    invariant TodoApp.Domain.User.Specs.NoDuplicateAchievements, on: :achievements
    invariant TodoApp.Domain.User.Specs.AchievementsAreEarned
  end

  # Record how many tasks the user has completed, and award every achievement that count
  # earns. The count is *set*, not incremented, and never goes down, so calling it again with
  # the same number is a no-op: it is safe to repeat (events are delivered at least once).
  defop record_progress(user, completed) when is_integer(completed) do
    user = %{user | completed_tasks: max(user.completed_tasks, completed)}
    held = Enum.map(user.achievements, & &1.code)

    Enum.reduce(Achievements.earned_by(user) -- held, user, fn code, acc ->
      {:ok, achievement} = Achievement.new(code: code, awarded_at: DateTime.utc_now())

      %{acc | achievements: acc.achievements ++ [achievement]}
      |> emit_event(Events.AchievementEarned.new(%{code: Atom.to_string(code)}))
    end)
  end
end

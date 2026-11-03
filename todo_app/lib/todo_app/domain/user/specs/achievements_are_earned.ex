defmodule TodoApp.Domain.User.Specs.AchievementsAreEarned do
  @moduledoc """
  Every achievement a user holds must be justified by their progress, according to the
  catalog. Nothing can hand out an achievement that was not earned.
  """
  use DDD.Specification, field: :achievements

  @impl DDD.Specification
  def check(%{achievements: achievements} = user, _opts) do
    earned = TodoApp.Domain.User.Achievements.earned_by(user)

    case Enum.reject(achievements, &(&1.code in earned)) do
      [] ->
        :ok

      unearned ->
        {:error, :achievement_not_earned, "holds achievements that were not earned",
         %{codes: Enum.map(unearned, & &1.code)}}
    end
  end
end

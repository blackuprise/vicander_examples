defmodule TodoApp.Application.Queries.User.AchievementsOf do
  @moduledoc "The achievements a user has earned."
  use DDD.Query

  alias TodoApp.Domain.User.Achievements
  alias TodoApp.Domain.User.Repository, as: UserRepository

  query do
    description "The achievements a user has earned and when, without any personal data"

    field :user_id, :uuid, required: true, description: "The id of the user"
  end

  @impl DDD.Query
  def execute(%__MODULE__{user_id: user_id}) do
    case UserRepository.impl().find_by_id(user_id) do
      {:ok, user} ->
        {:ok,
         for achievement <- user.achievements do
           %{
             code: achievement.code,
             title: Achievements.get(achievement.code).title,
             awarded_at: achievement.awarded_at
           }
         end}

      {:error, :not_found} ->
        {:error, {:user_not_found, "user #{user_id} does not exist"}}
    end
  end
end

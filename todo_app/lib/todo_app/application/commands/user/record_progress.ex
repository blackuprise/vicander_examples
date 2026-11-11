defmodule TodoApp.Application.Commands.User.RecordProgress do
  @moduledoc """
  Recompute a user's completed-task count from their lists and award the achievements it
  earns.

  The count is derived from the lists (the source of truth), not incremented per event, so
  running this twice, or for an event delivered twice, changes nothing the second time.
  """
  use DDD.Command
  require Logger

  alias TodoApp.Domain.TodoList.Repository, as: TodoListRepository
  alias TodoApp.Domain.User
  alias TodoApp.Domain.User.Achievements
  alias TodoApp.Domain.User.Repository, as: UserRepository

  command do
    description "Recount a user's completed tasks from their lists and award the achievements it earns. " <>
                  "Safe to repeat: running it again changes nothing."

    field :owner_id, :uuid,
      required: true,
      loads: User,
      description: "The id of the user to recount"
  end

  @impl DDD.Command
  def execute(%__MODULE__{owner_id: owner_id}) do
    with {:ok, user} <- UserRepository.impl().find_by_id(owner_id),
         {:ok, updated} <- User.record_progress(user, completed_tasks(owner_id)),
         {:ok, saved} <- UserRepository.impl().save(updated) do
      log_progress(user, saved)
      {:ok, saved}
    end
  end

  defp log_progress(before, saved) do
    Logger.info("[achievements] #{saved.email}: #{saved.completed_tasks} task(s) completed")

    for achievement <- saved.achievements,
        achievement.code not in Enum.map(before.achievements, & &1.code) do
      %{title: title, description: description} = Achievements.get(achievement.code)
      Logger.info("[achievements] #{saved.email} earned #{title}: #{description}")
    end
  end

  defp completed_tasks(owner_id) do
    owner_id
    |> TodoListRepository.impl().find_by_owner_id()
    |> Enum.flat_map(& &1.items)
    |> Enum.count(&(&1.status == :done))
  end
end

defmodule TodoApp.Application.Handlers.User.AchievementTracker do
  @moduledoc """
  Reacts to `ItemCompleted` (delivered through the outbox) by recording the owner's progress.

  The event is linked to its list (`aggregate_id`), and the list knows its owner.

  It runs in a transaction together with its delivery record (the default for
  `DDD.EventHandler`). The user it saves and the `AchievementEarned` events that save writes
  to the outbox commit with that record or not at all, so a failure never leaves half of the
  work behind, and a retry never repeats work that was already committed. `RecordProgress` is
  also idempotent on its own.

  A delivery runs in a unit of work, like a command: what `RecordProgress` saves is written,
  in one statement with its events, just before the delivery commits.

  Two events for the same user handled at the same moment cannot overwrite each other: the
  repository saves with optimistic locking, so the second write fails with `:stale_aggregate`
  (an infrastructure error, so the outbox retries the delivery). The retry recomputes from the
  lists and sees both.
  """
  require Logger

  alias TodoApp.Application.Commands.User.RecordProgress
  alias TodoApp.Domain.TodoList.Events.ItemCompleted
  alias TodoApp.Domain.TodoList.Repository, as: TodoListRepository

  use DDD.EventHandler, events: [TodoApp.Domain.TodoList.Events.ItemCompleted]

  @impl DDD.EventHandler
  def handle(%ItemCompleted{aggregate_id: list_id}) do
    with {:ok, list} <- TodoListRepository.impl().find_by_id(list_id),
         :ok <- announce(list_id, list.owner_id),
         {:ok, _user} <- RecordProgress.call(%{owner_id: list.owner_id}) do
      :ok
    else
      # Already an `{:error, reason}`: pass it on as it is, so the outbox sees the real reason.
      {:error, reason} = error ->
        Logger.warning(
          "[achievements] could not record progress for list #{list_id}: #{inspect(reason)}"
        )

        error
    end
  end

  defp announce(list_id, owner_id) do
    Logger.info(
      "[achievements] item completed in list #{list_id}; recording progress for #{owner_id}"
    )
  end
end

defmodule TodoApp.Infrastructure.EventLogger do
  @moduledoc """
  Logs every todo event delivered through the outbox.

  It only logs, so there is nothing for a database transaction to protect: `transaction: false`.
  """
  require Logger

  use DDD.EventHandler,
    events: [
      TodoApp.Domain.TodoList.Events.ItemAdded,
      TodoApp.Domain.TodoList.Events.ItemCompleted,
      TodoApp.Domain.User.Events.AchievementEarned
    ],
    transaction: false

  @impl DDD.EventHandler
  def handle(event) do
    Logger.info("[todo] #{event.__struct__.event_name()} #{inspect(Map.from_struct(event))}")
  end
end

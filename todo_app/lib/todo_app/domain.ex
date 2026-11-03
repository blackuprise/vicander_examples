defmodule TodoApp.Domain do
  @moduledoc """
  The domain layer: aggregates, entities, value objects, specifications, events and the
  repository ports. It knows only the `DDD` framework: it can't reach the application or
  infrastructure layers, nor Ecto and the database.

  Only the modules listed in `exports` are visible outside; the specifications are internal.
  """
  use Boundary,
    top_level?: true,
    deps: [],
    check: [apps: [:ecto, :ecto_sql, :postgrex]],
    exports: [
      TodoList,
      TodoList.TodoItem,
      TodoList.Title,
      TodoList.Repository,
      TodoList.Events.ItemAdded,
      TodoList.Events.ItemCompleted,
      User,
      User.Achievements,
      User.Achievement,
      User.Repository,
      User.Events.AchievementEarned
    ]
end

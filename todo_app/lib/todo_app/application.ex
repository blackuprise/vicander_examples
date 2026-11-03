defmodule TodoApp.Application do
  @moduledoc """
  The application layer: commands, queries, event handlers and the projections (read models)
  the queries read. It orchestrates the domain
  through its repository ports and never touches infrastructure directly.
  """
  use Boundary,
    top_level?: true,
    deps: [TodoApp.Domain],
    exports: [
      Commands.TodoList.CreateList,
      Commands.TodoList.AddItem,
      Commands.TodoList.CompleteItem,
      Commands.TodoList.RenameItem,
      Commands.User.RegisterUser,
      Commands.User.RecordProgress,
      Queries.TodoList.OpenItems,
      Queries.TodoList.ListsOfOwner,
      Queries.TodoList.SearchLists,
      Queries.TodoList.ListActivity,
      Queries.User.AchievementsOf,
      Handlers.User.AchievementTracker,
      Projections.TodoList.ListStats
    ]
end

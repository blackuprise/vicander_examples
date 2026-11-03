defmodule TodoApp.Interface.MCP do
  @moduledoc """
  The todo application as an MCP server.

      mix vic.mcp TodoApp.Interface.MCP                  # serve on stdin/stdout
      mix vic.mcp TodoApp.Interface.MCP --read-only      # queries and resources only

      claude mcp add todo -- mix vic.mcp TodoApp.Interface.MCP

  Commands change data and queries only read. Both are tools; the lists and users are also
  readable as resources (`todo_list://<id>`, `todo_list://by/owner_id/<owner id>`). Every field
  of a resource is shown, including a user's email.
  """
  use DDD.MCP.Server,
    instructions:
      "A todo application. Register a user, create a list for them, then add, rename and " <>
        "complete items. Use the queries to read; ids are UUIDs.",
    commands: [
      TodoApp.Application.Commands.User.RegisterUser,
      TodoApp.Application.Commands.User.RecordProgress,
      TodoApp.Application.Commands.TodoList.CreateList,
      TodoApp.Application.Commands.TodoList.AddItem,
      TodoApp.Application.Commands.TodoList.RenameItem,
      TodoApp.Application.Commands.TodoList.CompleteItem
    ],
    queries: [
      TodoApp.Application.Queries.TodoList.OpenItems,
      TodoApp.Application.Queries.TodoList.ListsOfOwner,
      TodoApp.Application.Queries.TodoList.SearchLists,
      TodoApp.Application.Queries.TodoList.ListActivity,
      TodoApp.Application.Queries.User.AchievementsOf
    ],
    repos: [
      TodoApp.Domain.TodoList.Repository,
      TodoApp.Domain.User.Repository
    ]
end

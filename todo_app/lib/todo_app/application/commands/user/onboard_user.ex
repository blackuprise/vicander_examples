defmodule TodoApp.Application.Commands.User.OnboardUser do
  @moduledoc """
  Register a user and give them a first list with a welcome item: three commands in one, all or
  nothing.

  A command may call other commands. They join this one's transaction and unit of work, so
  nothing is written until the whole chain has finished, and then it is written together: one
  `INSERT` for the user, one for the list, one for their events. If a step fails, nothing was
  written at all.

  What makes this chain work is that each step only asks for what an earlier step saved **by its
  id**. `CreateList` loads its owner, which the unit of work already holds although it is not in
  the database yet, and `AddItem` does the same with the list.

  What would not work is a step that *queries* after an earlier step saved something: the
  database does not have that yet, so the repository raises
  `DDD.UnitOfWork.PendingChangesError` instead of giving a wrong answer.
  `RecordProgress` is such a command (it looks up the user's lists with `find_by_owner_id`), so it
  cannot follow `CompleteItem` in a chain. The application connects the two with an event
  instead (`Handlers.User.AchievementTracker`); see `test/chaining_test.exs`.
  """
  use DDD.Command

  alias TodoApp.Application.Commands

  command do
    description "Register a user and create their first list with a welcome item. " <>
                  "Either all of it happens or none."

    field :name, :string, required: true, description: "The user's name"
    field :email, :string, required: true, description: "The user's email address"
  end

  @impl DDD.Command
  def execute(%__MODULE__{name: name, email: email}) do
    with {:ok, user} <- Commands.User.RegisterUser.call(%{name: name, email: email}),
         {:ok, list} <-
           Commands.TodoList.CreateList.call(%{owner_id: user.id, name: "Getting started"}),
         {:ok, list} <-
           Commands.TodoList.AddItem.call(%{list_id: list.id, title: "Welcome to your list"}) do
      {:ok, %{user: user, list: list}}
    end
  end
end

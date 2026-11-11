defmodule TodoApp.PortsTest do
  @moduledoc """
  The application layer only names the domain's ports, so an adapter is a configuration choice.
  Here both Postgres adapters are replaced by in-memory ones, and real commands run against them.
  """
  use TodoApp.DataCase

  alias TodoApp.Application.Commands
  alias TodoApp.Domain.TodoList.Repository, as: TodoListRepository
  alias TodoApp.Domain.User.Repository, as: UserRepository

  defmodule MemoryUsers do
    @moduledoc false
    use DDD.InMemoryRepository, port: TodoApp.Domain.User.Repository

    def find_by_email(email), do: Enum.filter(all(), &(&1.email == email))
  end

  defmodule MemoryLists do
    @moduledoc false
    use DDD.InMemoryRepository, port: TodoApp.Domain.TodoList.Repository

    def find_by_owner_id(owner_id), do: Enum.filter(all(), &(&1.owner_id == owner_id))
  end

  setup do
    original = Application.fetch_env!(:todo_app, :repositories)
    start_supervised!(MemoryUsers)
    start_supervised!(MemoryLists)

    Application.put_env(:todo_app, :repositories, todo_list: MemoryLists, user: MemoryUsers)
    on_exit(fn -> Application.put_env(:todo_app, :repositories, original) end)
    :ok
  end

  test "ports resolve to the configured adapters" do
    assert UserRepository.impl() == MemoryUsers
    assert TodoListRepository.impl() == MemoryLists
  end

  test "the default configuration uses the Postgres adapters" do
    Application.put_env(:todo_app, :repositories,
      todo_list: TodoApp.Infrastructure.TodoList.Repository,
      user: TodoApp.Infrastructure.User.Repository
    )

    assert TodoListRepository.impl() == TodoApp.Infrastructure.TodoList.Repository
    assert UserRepository.impl() == TodoApp.Infrastructure.User.Repository
  end

  test "commands run end to end against the in-memory adapters, and the database is untouched" do
    {:ok, user} = Commands.User.RegisterUser.call(%{name: "Ann", email: "ann@example.com"})
    {:ok, list} = Commands.TodoList.CreateList.call(%{owner_id: user.id, name: "Home"})
    {:ok, list} = Commands.TodoList.AddItem.call(%{list_id: list.id, title: "Buy milk"})
    [item] = list.items
    {:ok, done} = Commands.TodoList.CompleteItem.call(%{list_id: list.id, item_id: item.id})

    assert [%{status: :done}] = done.items
    assert {:ok, ^done} = MemoryLists.find_by_id(list.id)
    assert {:ok, ^user} = MemoryUsers.find_by_id(user.id)

    # Recording progress reads the lists through the port too.
    {:ok, progressed} = Commands.User.RecordProgress.call(%{owner_id: user.id})
    assert progressed.completed_tasks == 1
    assert [%{code: :newbie}] = progressed.achievements

    for table <- ~w(users todo_lists domain_events) do
      assert %{rows: [[0]]} = Repo.query!("SELECT count(*) FROM #{table}")
    end
  end

  test "domain rules are the same whatever the adapter" do
    {:ok, user} = Commands.User.RegisterUser.call(%{name: "Ann", email: "ann@example.com"})
    {:ok, list} = Commands.TodoList.CreateList.call(%{owner_id: user.id, name: "Home"})

    assert {:error, error} =
             Commands.TodoList.CompleteItem.call(%{
               list_id: list.id,
               item_id: DDD.Identity.generate()
             })

    assert DDD.Error.has_code?(error, :item_not_found)

    assert {:error, %{code: :not_found}} =
             Commands.TodoList.CreateList.call(%{owner_id: DDD.Identity.generate(), name: "x"})
  end
end

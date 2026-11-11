defmodule TodoApp.ConcurrentEditsTest do
  @moduledoc """
  Several people editing one list at the same time, on real connections and with real commits.

  Each edit loads the list, changes it and saves it with its version. When two overlap, the
  second finds the list changed by the first and loses (`:stale_aggregate`). The commands that
  edit a list say `retry_on_conflict: 3`: a loser runs again on the list as it is now (waiting a
  random moment first, so the losers do not collide again), and every edit lands.
  """
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias TodoApp.Application.Commands
  alias TodoApp.Infrastructure.Repo
  alias TodoApp.Infrastructure.TodoList.Repository, as: TodoListRepository

  setup do
    # The sandbox would give every process the same connection and serialize them.
    Sandbox.mode(Repo, :auto)

    on_exit(fn ->
      Repo.query!(
        "TRUNCATE todo_list_stats, event_deliveries, domain_events, todo_lists, users CASCADE"
      )

      Sandbox.mode(Repo, :manual)
    end)

    {:ok, user} = Commands.User.RegisterUser.call(%{name: "Ann", email: "ann@example.com"})
    {:ok, list} = Commands.TodoList.CreateList.call(%{owner_id: user.id, name: "Home"})
    %{list: list}
  end

  test "four people adding items to one list all succeed", %{list: list} do
    # Four contenders: each round at least one wins, so nobody can lose more than three times,
    # which is what `retry_on_conflict: 3` allows.
    results =
      1..4
      |> Task.async_stream(
        fn n -> Commands.TodoList.AddItem.call(%{list_id: list.id, title: "Item #{n}"}) end,
        max_concurrency: 4,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, _}, &1)), inspect(results)

    assert {:ok, stored} = TodoListRepository.find_by_id(list.id)

    assert stored.items |> Enum.map(& &1.title.value) |> Enum.sort() ==
             for(n <- 1..4, do: "Item #{n}")

    # Every item, once: nothing lost to a race, nothing written twice.
    assert Repo.query!("SELECT count(*) FROM domain_events WHERE event_type LIKE '%ItemAdded'").rows ==
             [[4]]
  end

  test "completing the same item twice at once: one wins, the other is told it is done", %{
    list: list
  } do
    {:ok, with_item} = Commands.TodoList.AddItem.call(%{list_id: list.id, title: "Only one"})
    [item] = with_item.items

    results =
      1..2
      |> Task.async_stream(
        fn _ ->
          Commands.TodoList.CompleteItem.call(%{list_id: list.id, item_id: item.id})
        end,
        max_concurrency: 2,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    # The loser ran again on the list as the winner left it, and the rule refused it: a business
    # answer, not a lost race.
    assert [{:error, %DDD.Error{kind: :business} = error}] =
             Enum.filter(results, &match?({:error, _}, &1))

    assert DDD.Error.has_code?(error, :already_completed)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
  end
end

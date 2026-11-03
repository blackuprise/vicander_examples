defmodule TodoApp.ListStatsTest do
  use TodoApp.DataCase

  @moduletag :capture_log

  alias DDD.Outbox.Poller
  alias TodoApp.Application.Commands
  alias TodoApp.Application.Projections.TodoList.ListStats

  setup do
    start_supervised!({Poller, repo: Repo, interval_ms: 600_000})
    ListStats.subscribe()
    on_exit(&ListStats.unsubscribe/0)

    {:ok, user} = Commands.User.RegisterUser.call(%{name: "Ann", email: "ann@example.com"})
    {:ok, list} = Commands.TodoList.CreateList.call(%{owner_id: user.id, name: "Home"})
    %{list: list}
  end

  defp add_item!(list, title) do
    {:ok, with_item} = Commands.TodoList.AddItem.call(%{list_id: list.id, title: title})
    List.last(with_item.items)
  end

  test "follows the list as items are added and completed", %{list: list} do
    first = add_item!(list, "milk")
    add_item!(list, "eggs")
    {:ok, _} = Commands.TodoList.CompleteItem.call(%{list_id: list.id, item_id: first.id})

    # Nothing is projected until the outbox delivers.
    assert {:error, :not_found} = ListStats.get(list.id)
    assert %{pending: 3} = ListStats.lag()

    assert {:ok, 3} = Poller.poll_now()

    assert {:ok, %{items_added: 2, items_completed: 1, last_activity_at: %DateTime{}}} =
             ListStats.get(list.id)

    assert %{pending: 0} = ListStats.lag()
  end

  test "lists are counted separately, and can be listed, ordered and paged", %{list: list} do
    {:ok, other} = Commands.TodoList.CreateList.call(%{owner_id: list.owner_id, name: "Work"})

    add_item!(list, "milk")
    add_item!(other, "report")
    add_item!(other, "slides")
    assert {:ok, 3} = Poller.poll_now()

    assert {:ok, %DDD.Page{entries: [busiest, quietest], total_entries: 2}} =
             ListStats.page(order: [desc: :items_added])

    assert {busiest.list_id, busiest.items_added} == {other.id, 2}
    assert {quietest.list_id, quietest.items_added} == {list.id, 1}

    assert {:ok, [%{list_id: id}]} = ListStats.list(filter: [items_added: {:gte, 2}])
    assert id == other.id
  end

  test "rebuilding from the stored events gives the same numbers", %{list: list} do
    first = add_item!(list, "milk")
    {:ok, _} = Commands.TodoList.CompleteItem.call(%{list_id: list.id, item_id: first.id})
    assert {:ok, 2} = Poller.poll_now()
    {:ok, before} = ListStats.get(list.id)

    Repo.query!("UPDATE todo_list_stats SET items_added = 40")

    assert {:ok, %{events: 2}} = ListStats.rebuild()
    assert {:ok, ^before} = ListStats.get(list.id)
  end

  test "is part of the health check", %{list: list} do
    add_item!(list, "milk")

    assert %{
             checks: %{
               projections: %{"TodoApp.Application.Projections.TodoList.ListStats" => lag}
             }
           } =
             DDD.Health.check()

    assert %{pending: 1} = lag
  end
end

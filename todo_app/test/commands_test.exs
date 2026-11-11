defmodule TodoApp.CommandsTest do
  use TodoApp.DataCase

  import ExUnit.CaptureLog

  alias DDD.Error
  alias TodoApp.Application.Commands
  alias TodoApp.Domain.TodoList
  alias TodoApp.Domain.TodoList.{Title, TodoItem}
  alias TodoApp.Infrastructure.TodoList.Repository, as: TodoListRepository
  alias TodoApp.Infrastructure.User.Repository, as: UserRepository

  defmodule Forwarder do
    @moduledoc false
    def handle(event) do
      if pid = :persistent_term.get({__MODULE__, :pid}, nil), do: send(pid, {:event, event})
    end
  end

  defp register!(email \\ "ann@example.com") do
    {:ok, user} = Commands.User.RegisterUser.call(%{name: "Ann", email: email})
    user
  end

  defp create_list!(user) do
    {:ok, list} = Commands.TodoList.CreateList.call(%{owner_id: user.id, name: "Home"})
    list
  end

  defp add_item!(list, title, due_date \\ nil) do
    {:ok, list} =
      Commands.TodoList.AddItem.call(%{list_id: list.id, title: title, due_date: due_date})

    list
  end

  describe "RegisterUser" do
    test "saves a user" do
      user = register!()
      assert {:ok, ^user} = UserRepository.find_by_id(user.id)
      assert [^user] = UserRepository.find_by_email("ann@example.com")
    end

    test "returns the domain error with the command in its context" do
      assert {:error, %Error{} = error} =
               Commands.User.RegisterUser.call(%{name: "Ann", email: "nope"})

      assert Error.to_map(error) == %{email: ["must be a valid email address"]}
      assert error.entity == TodoApp.Domain.User
      assert error.context == %{command: Commands.User.RegisterUser}
    end
  end

  describe "CreateList" do
    test "creates a list for an existing owner" do
      user = register!()
      list = create_list!(user)

      assert {:ok, ^list} = TodoListRepository.find_by_id(list.id)
      assert [^list] = TodoListRepository.find_by_owner_id(user.id)
      assert list.items == []
    end

    test "fails when the owner does not exist" do
      missing = DDD.Identity.generate()

      # `loads:` on the owner reads it before the command runs, and names what is missing.
      assert {:error, %Error{code: :not_found, kind: :business} = error} =
               Commands.TodoList.CreateList.call(%{owner_id: missing, name: "Home"})

      assert error.entity == TodoApp.Domain.User
      assert error.entity_id == missing
      assert error.details == %{field: :owner_id, missing_ids: [missing]}
      assert error.context.command == Commands.TodoList.CreateList
    end
  end

  describe "items" do
    setup do
      %{list: create_list!(register!())}
    end

    test "nested entities survive a save and reload as sealed structs", %{list: list} do
      due = Date.add(Date.utc_today(), 2)
      saved = add_item!(list, "Buy milk", due)
      assert {:ok, loaded} = TodoListRepository.find_by_id(list.id)
      assert loaded == saved

      assert [%TodoItem{title: %Title{value: "Buy milk"}, due_date: ^due, status: :open} = item] =
               loaded.items

      assert DDD.Schema.sealed?(item)
      assert DDD.Schema.sealed?(item.title)
      assert DDD.Schema.sealed?(loaded)
    end

    test "completing and renaming are persisted", %{list: list} do
      list = add_item!(list, "Buy milk")
      [item] = list.items

      assert {:ok, renamed} =
               Commands.TodoList.RenameItem.call(%{
                 list_id: list.id,
                 item_id: item.id,
                 title: "Oat milk"
               })

      assert [%{title: %{value: "Oat milk"}}] = renamed.items

      assert {:ok, done} =
               Commands.TodoList.CompleteItem.call(%{
                 list_id: list.id,
                 item_id: item.id
               })

      assert [%{status: :done, completed_at: %DateTime{}}] = done.items

      assert {:ok, ^done} = TodoListRepository.find_by_id(list.id)
    end

    test "a done item cannot be renamed; the error names the entity, operation and command", %{
      list: list
    } do
      list = add_item!(list, "Buy milk")
      [item] = list.items

      {:ok, _} =
        Commands.TodoList.CompleteItem.call(%{list_id: list.id, item_id: item.id})

      assert {:error, %Error{} = error} =
               Commands.TodoList.RenameItem.call(%{
                 list_id: list.id,
                 item_id: item.id,
                 title: "x"
               })

      assert error.kind == :business
      assert error.code == :precondition_failed
      assert Error.codes(error) == [:item_completed]
      assert error.message == "a completed item cannot be edited"
      assert error.entity == TodoList
      assert error.operation == :rename_item
      assert error.context == %{command: Commands.TodoList.RenameItem}
    end

    test "the 11th open item is rejected and nothing is saved", %{list: list} do
      list = Enum.reduce(1..10, list, fn n, acc -> add_item!(acc, "item #{n}") end)

      assert {:error, %Error{} = error} =
               Commands.TodoList.AddItem.call(%{list_id: list.id, title: "one too many"})

      assert Error.has_code?(error, :too_many_open_items)
      assert {:ok, reloaded} = TodoListRepository.find_by_id(list.id)
      assert length(reloaded.items) == 10
    end

    test "domain rules reach the caller: blank title, past due date, long title", %{list: list} do
      assert {:error, e1} = Commands.TodoList.AddItem.call(%{list_id: list.id, title: " "})
      assert Error.has_code?(e1, :title_blank)

      past = Date.add(Date.utc_today(), -1)

      assert {:error, e2} =
               Commands.TodoList.AddItem.call(%{
                 list_id: list.id,
                 title: "x",
                 due_date: past
               })

      assert Error.has_code?(e2, :due_date_in_past)

      assert {:error, e3} =
               Commands.TodoList.AddItem.call(%{
                 list_id: list.id,
                 title: String.duplicate("a", 101)
               })

      assert e3.entity == Title
    end

    test "unknown list and unknown item", %{list: list} do
      assert {:error, %Error{code: :not_found, entity: TodoApp.Domain.TodoList}} =
               Commands.TodoList.AddItem.call(%{list_id: DDD.Identity.generate(), title: "x"})

      assert {:error, %Error{} = error} =
               Commands.TodoList.CompleteItem.call(%{
                 list_id: list.id,
                 item_id: DDD.Identity.generate()
               })

      assert error.code == :precondition_failed
      assert Error.codes(error) == [:item_not_found]
      assert error.context == %{command: Commands.TodoList.CompleteItem}
    end

    test "a missing command field is a validation error from the command" do
      assert {:error, %Error{} = error} =
               Commands.TodoList.AddItem.new(%{list_id: DDD.Identity.generate()})

      assert Error.to_map(error) == %{title: ["is required"]}
    end

    test "a field of the wrong type is a validation error from the command" do
      assert {:error, %Error{} = error} =
               Commands.TodoList.AddItem.new(%{list_id: "x", title: 5})

      assert Error.to_map(error) == %{list_id: ["must be a uuid"], title: ["must be a string"]}
    end
  end

  describe "repository" do
    test "refuses to save a list that was not produced by the framework" do
      list = create_list!(register!())
      tampered = %{list | name: "sneaky"}

      log =
        capture_log(fn ->
          assert {:error, %Error{code: :unsealed, entity: TodoList}} =
                   TodoListRepository.save(tampered)
        end)

      assert log =~ "[repo] refused to save TodoApp.Domain.TodoList #{list.id}"
      assert {:ok, %{name: "Home"}} = TodoListRepository.find_by_id(list.id)
    end

    test "deletes lists" do
      list = create_list!(register!())
      assert :ok = TodoListRepository.delete(list)
      assert {:error, :not_found} = TodoListRepository.find_by_id(list.id)
      assert {:error, :not_found} = TodoListRepository.delete(list)
    end

    test "rows written before an item gained fields still load, with defaults" do
      user = register!()
      list_id = DDD.Identity.generate()
      now = DateTime.utc_now()

      old_item = %{
        "id" => DDD.Identity.generate(),
        "title" => %{"value" => "Old"},
        "status" => "open"
      }

      Repo.insert_all("todo_lists", [
        %{
          id: Ecto.UUID.dump!(list_id),
          owner_id: Ecto.UUID.dump!(user.id),
          name: "Legacy",
          items: [old_item],
          created_at: now,
          updated_at: now
        }
      ])

      assert {:ok, %{items: [item]}} = TodoListRepository.find_by_id(list_id)
      assert item.due_date == nil
      assert item.completed_at == nil
      assert item.status == :open
    end

    test "table columns match the aggregates (no schema drift)" do
      assert :ok = DDD.Migration.drift(TodoApp.Domain.TodoList, "todo_lists", Repo)
      assert :ok = DDD.Migration.drift(TodoApp.Domain.User, "users", Repo)

      assert {:error, %{missing_in_db: missing, extra_in_db: extra}} =
               DDD.Migration.drift(TodoApp.Domain.TodoList, "users", Repo)

      assert "items" in missing
      assert "email" in extra
    end
  end

  describe "events and the outbox" do
    setup do
      :persistent_term.put({Forwarder, :pid}, self())
      DDD.EventBus.subscribe(TodoApp.Domain.TodoList.Events.ItemAdded, Forwarder)
      DDD.EventBus.subscribe(TodoApp.Domain.TodoList.Events.ItemCompleted, Forwarder)
      TodoApp.Infrastructure.EventLogger.subscribe()

      on_exit(fn ->
        TodoApp.Infrastructure.EventLogger.unsubscribe()
        DDD.EventBus.unsubscribe(TodoApp.Domain.TodoList.Events.ItemAdded, Forwarder)
        DDD.EventBus.unsubscribe(TodoApp.Domain.TodoList.Events.ItemCompleted, Forwarder)
      end)

      start_supervised!({DDD.Outbox.Poller, repo: Repo, interval_ms: 600_000})
      :ok
    end

    test "events are written with the aggregate and delivered once published" do
      list = create_list!(register!())
      list = add_item!(list, "Buy milk")
      [item] = list.items

      {:ok, _} =
        Commands.TodoList.CompleteItem.call(%{list_id: list.id, item_id: item.id})

      assert %{
               rows: [
                 ["TodoApp.Domain.TodoList.Events.ItemAdded"],
                 ["TodoApp.Domain.TodoList.Events.ItemCompleted"]
               ]
             } =
               Repo.query!("SELECT event_type FROM domain_events ORDER BY occurred_at")

      assert {:ok, 2} = DDD.Outbox.Poller.poll_now()

      assert_receive {:event,
                      %TodoApp.Domain.TodoList.Events.ItemAdded{
                        title: "Buy milk",
                        item_id: item_id
                      } =
                        added}

      assert item_id == item.id

      # Every event is linked to its aggregate (type, id) and carries created_at.
      assert added.aggregate_type == "TodoApp.Domain.TodoList"
      assert added.aggregate_id == list.id
      assert %DateTime{} = added.created_at
      assert String.length(added.event_id) == 36

      assert_receive {:event, %TodoApp.Domain.TodoList.Events.ItemCompleted{} = completed}
      assert completed.aggregate_type == "TodoApp.Domain.TodoList"
      assert completed.aggregate_id == list.id
      assert %DateTime{} = completed.created_at

      assert %{rows: [["TodoApp.Domain.TodoList", list_id], ["TodoApp.Domain.TodoList", list_id]]} =
               Repo.query!(
                 "SELECT aggregate_type, aggregate_id FROM domain_events ORDER BY occurred_at"
               )

      assert list_id == list.id

      assert {:ok, 0} = DDD.Outbox.Poller.poll_now()
    end

    test "the logger handler logs every todo event" do
      log =
        capture_log(fn ->
          TodoApp.Infrastructure.EventLogger.handle(
            TodoApp.Domain.TodoList.Events.ItemAdded.new(%{title: "Buy milk"})
          )
        end)

      assert log =~ "[todo] item_added"
      assert log =~ "Buy milk"
    end

    test "a failed operation writes no event" do
      list = create_list!(register!())
      {:error, _} = Commands.TodoList.AddItem.call(%{list_id: list.id, title: " "})
      assert %{rows: [[0]]} = Repo.query!("SELECT count(*) FROM domain_events")
    end

    test "an event of an unknown type is logged, left unpublished and retried later" do
      now = DateTime.utc_now()

      Repo.insert_all("domain_events", [
        %{
          id: Ecto.UUID.dump!(DDD.Identity.generate()),
          event_type: "No.Such.Event",
          aggregate_id: "1",
          aggregate_type: "X",
          payload: %{},
          occurred_at: now,
          inserted_at: now
        }
      ])

      log = capture_log(fn -> assert {:ok, 1} = DDD.Outbox.Poller.poll_now() end)
      assert log =~ "delivery of No.Such.Event"
      assert log =~ "unknown_event_module"

      assert %{rows: [[1, "{:unknown_event_module" <> _, nil]]} =
               Repo.query!("SELECT attempts, last_error, published_at FROM domain_events")

      # The retry is delayed by the backoff, so an immediate poll finds nothing due.
      assert {:ok, 0} = DDD.Outbox.Poller.poll_now()
    end

    test "the periodic poll runs on its own" do
      stop_supervised!(DDD.Outbox.Poller)
      start_supervised!({DDD.Outbox.Poller, repo: Repo, interval_ms: 10})
      list = create_list!(register!())
      add_item!(list, "Buy milk")
      assert_receive {:event, %TodoApp.Domain.TodoList.Events.ItemAdded{}}, 2_000

      # Stop the poller before the test ends so it is never mid-query when the sandbox closes.
      stop_supervised!(DDD.Outbox.Poller)
    end
  end
end

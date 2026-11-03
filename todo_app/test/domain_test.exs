defmodule TodoApp.DomainTest do
  use ExUnit.Case, async: true

  alias DDD.Error
  alias TodoApp.Domain.{TodoList, User}
  alias TodoApp.Domain.TodoList.{Events, Title, TodoItem}

  defp title!(value) do
    {:ok, title} = Title.new(value: value)
    title
  end

  defp item!(value \\ "Buy milk", attrs \\ []) do
    {:ok, item} = TodoItem.new([title: title!(value)] ++ attrs)
    item
  end

  defp list! do
    {:ok, list} = TodoList.new(owner_id: UUID.uuid4(), name: "Home")
    list
  end

  defp list_with!(items) do
    Enum.reduce(items, list!(), fn item, list ->
      {:ok, list} = TodoList.add_item(list, item)
      list
    end)
  end

  describe "Title" do
    test "is at most 100 characters" do
      assert {:ok, _} = Title.new(value: String.duplicate("a", 100))
      assert {:error, error} = Title.new(value: String.duplicate("a", 101))
      assert Error.to_map(error) == %{value: ["must be at most 100 characters"]}
    end

    test "equality is by value" do
      assert Title.equals?(title!("a"), title!("a"))
      refute Title.equals?(title!("a"), title!("b"))
    end
  end

  describe "User" do
    test "needs a name and a valid email" do
      assert {:ok, _} = User.new(name: "Ann", email: "ann@example.com")
      assert {:error, error} = User.new(name: "Ann", email: "nope")
      assert Error.to_map(error) == %{email: ["must be a valid email address"]}
      assert {:error, error} = User.new(%{})
      assert Error.codes(error) == [:required, :required]
    end
  end

  describe "TodoItem specs" do
    test "a blank title is rejected, reported under :title" do
      assert {:error, error} = TodoItem.new(title: title!("   "))
      assert [%{field: :title, code: :title_blank}] = error.violations
    end

    test "a title is required" do
      assert {:error, error} = TodoItem.new(%{})
      assert Error.codes(error) == [:required]
    end

    test "a due date in the past is rejected, today and later are fine" do
      yesterday = Date.add(Date.utc_today(), -1)
      assert {:error, error} = TodoItem.new(title: title!("x"), due_date: yesterday)

      assert [%{field: :due_date, code: :due_date_in_past, details: %{due_date: ^yesterday}}] =
               error.violations

      assert {:ok, _} = TodoItem.new(title: title!("x"), due_date: Date.utc_today())
      assert {:ok, _} = TodoItem.new(title: title!("x"))
    end

    test "status must be open or done" do
      assert {:error, error} = TodoItem.new(title: title!("x"), status: :weird)
      assert Error.to_map(error) == %{status: ["must be one of [:open, :done]"]}
    end
  end

  describe "TodoItem priority and tags" do
    test "an item is normal and untagged unless told otherwise" do
      item = item!()
      assert item.priority == :normal
      assert item.tags == []
    end

    test "the priority is one of low, normal and high" do
      for priority <- [:low, :normal, :high] do
        assert {:ok, %{priority: ^priority}} =
                 TodoItem.new(title: title!("x"), priority: priority)
      end

      assert {:error, error} = TodoItem.new(title: title!("x"), priority: :urgent)
      assert Error.to_map(error) == %{priority: ["must be one of [:low, :normal, :high]"]}
    end

    test "tags are a list of strings" do
      assert {:ok, %{tags: ["a", "b"]}} = TodoItem.new(title: title!("x"), tags: ["a", "b"])
      assert {:error, error} = TodoItem.new(title: title!("x"), tags: ["a", 2])
      assert Error.codes(error) == [:invalid_type]
    end

    test "at most 5 tags, short, not blank, not repeated" do
      alias TodoApp.Domain.TodoList.Specs.TagsWithinLimit

      assert {:ok, _} = TodoItem.new(title: title!("x"), tags: Enum.map(1..5, &"t#{&1}"))

      for {tags, code} <- [
            {Enum.map(1..6, &"t#{&1}"), :too_many_tags},
            {["ok", " "], :blank_tag},
            {[String.duplicate("x", 21)], :tag_too_long},
            {["a", "b", "a"], :duplicate_tag}
          ] do
        assert {:error, error} = TodoItem.new(title: title!("x"), tags: tags)
        assert [%{field: :tags, code: ^code}] = error.violations
      end

      # The limits are options of the spec.
      assert :ok = TagsWithinLimit.check(["a", "b"], max: 2)

      assert {:error, :too_many_tags, _, %{max: 1, count: 2}} =
               TagsWithinLimit.check(["a", "b"], max: 1)

      assert {:error, :tag_too_long, _, _} = TagsWithinLimit.check(["abc"], max_length: 2)
    end

    test "items saved before these fields existed load with the defaults" do
      stored = %{"id" => UUID.uuid4(), "title" => %{"value" => "old"}, "status" => "open"}
      item = DDD.Serializer.load(TodoItem, stored)
      assert item.priority == :normal
      assert item.tags == []
      assert DDD.Schema.sealed?(item)
    end
  end

  describe "TodoItem operations" do
    test "complete marks the item done with a timestamp" do
      assert {:ok, done} = TodoItem.complete(item!())
      assert done.status == :done
      assert %DateTime{} = done.completed_at
    end

    test "a done item cannot be edited" do
      {:ok, done} = TodoItem.complete(item!())

      for {operation, result, rule, message} <- [
            {:rename, TodoItem.rename(done, title!("new")), :item_completed,
             "a completed item cannot be edited"},
            {:reschedule, TodoItem.reschedule(done, Date.utc_today()), :item_completed,
             "a completed item cannot be edited"},
            {:complete, TodoItem.complete(done), :already_completed, "item is already completed"}
          ] do
        # An explicit, named business rule: not a pattern-match failure.
        assert {:error, %Error{} = error} = result
        assert error.kind == :business
        assert error.code == :precondition_failed
        assert error.entity == TodoItem
        assert error.operation == operation
        assert error.message == message
        assert Error.codes(error) == [rule]
        assert [%{field: :status, details: %{status: :done}}] = error.violations
      end
    end

    test "arguments of the wrong shape are still :invalid_operation" do
      assert {:error, %Error{code: :invalid_operation, operation: :rename}} =
               TodoItem.rename(item!(), "not a Title struct")
    end

    test "rename and reschedule change an open item" do
      assert {:ok, %{title: %{value: "New"}}} = TodoItem.rename(item!(), title!("New"))
      tomorrow = Date.add(Date.utc_today(), 1)
      assert {:ok, %{due_date: ^tomorrow}} = TodoItem.reschedule(item!(), tomorrow)
    end

    test "renaming to a blank title is rejected by the spec" do
      assert {:error, error} = TodoItem.rename(item!(), title!(""))
      assert Error.has_code?(error, :title_blank)
    end

    test "rescheduling into the past is rejected by the spec" do
      assert {:error, error} = TodoItem.reschedule(item!(), Date.add(Date.utc_today(), -3))
      assert Error.has_code?(error, :due_date_in_past)
    end
  end

  describe "TodoList" do
    test "needs an owner and a non-blank name" do
      assert {:error, error} = TodoList.new(%{})
      assert Error.codes(error) == [:required, :required]
      assert {:error, error} = TodoList.new(owner_id: UUID.uuid4(), name: "  ")
      assert Error.to_map(error) == %{name: ["must not be blank"]}
    end

    test "add_item appends the item and emits ItemAdded" do
      item = item!("Buy milk")
      assert {:ok, list} = TodoList.add_item(list!(), item)
      assert [^item] = list.items
      assert [%Events.ItemAdded{title: "Buy milk", item_id: id} = event] = list.__pending_events__
      assert id == item.id
      assert event.aggregate_type == "TodoApp.Domain.TodoList"
      assert event.aggregate_id == list.id
    end

    test "a list holds at most 10 open items" do
      full = list_with!(for n <- 1..10, do: item!("item #{n}"))
      extra = item!("one too many")

      assert {:error, error} = TodoList.add_item(full, extra)

      assert [%{field: :items, code: :too_many_open_items, details: %{max: 10, open: 11}}] =
               error.violations

      assert error.entity == TodoList
      assert error.operation == :add_item
    end

    test "completing an item frees a slot, and emits ItemCompleted" do
      items = for n <- 1..10, do: item!("item #{n}")
      full = list_with!(items)
      {:ok, full} = Map.put(full, :__pending_events__, []) |> TodoList.validate()

      assert {:ok, list} = TodoList.complete_item(full, hd(items).id)
      assert [%Events.ItemCompleted{item_id: id}] = list.__pending_events__
      assert id == hd(items).id
      assert {:ok, list} = TodoList.add_item(list, item!("fits now"))
      assert length(list.items) == 11
    end

    test "an item that is not in the list is a precondition of the list's operation" do
      missing = UUID.uuid4()

      for {operation, result} <- [
            {:complete_item, TodoList.complete_item(list!(), missing)},
            {:rename_item, TodoList.rename_item(list!(), missing, title!("x"))}
          ] do
        assert {:error, %Error{} = error} = result
        assert error.kind == :business
        assert error.code == :precondition_failed
        assert error.entity == TodoList
        assert error.operation == operation
        assert error.message == "no item #{missing} in this list"
        assert Error.codes(error) == [:item_not_found]
        assert [%{field: :items, details: %{item_id: ^missing}}] = error.violations
      end
    end

    test "completing a done item is rejected by the list's own precondition" do
      item = item!()
      {:ok, list} = TodoList.add_item(list!(), item)
      {:ok, list} = TodoList.complete_item(list, item.id)

      # The error names what the caller invoked (the list operation), and the item's rule.
      assert {:error, %Error{} = error} = TodoList.complete_item(list, item.id)
      assert error.code == :precondition_failed
      assert error.entity == TodoList
      assert error.operation == :complete_item
      assert error.message == "item is already completed"
      assert Error.codes(error) == [:already_completed]
    end

    test "renaming a done item is rejected by the list's own precondition" do
      item = item!()
      {:ok, list} = TodoList.add_item(list!(), item)
      {:ok, list} = TodoList.complete_item(list, item.id)

      assert {:error, %Error{entity: TodoList, operation: :rename_item} = error} =
               TodoList.rename_item(list, item.id, title!("new"))

      assert Error.codes(error) == [:item_completed]
    end

    test "a missing item is reported once, not once per rule" do
      assert {:error, error} = TodoList.complete_item(list!(), UUID.uuid4())
      assert length(error.violations) == 1
    end

    test "the item's own operation still enforces its rule when called directly" do
      {:ok, done} = TodoItem.complete(item!())
      assert {:error, %Error{entity: TodoItem}} = TodoItem.complete(done)
    end

    test "a rejected completion emits no event and changes nothing" do
      item = item!()
      {:ok, list} = TodoList.add_item(list!(), item)
      {:ok, list} = TodoList.complete_item(list, item.id)
      {_, list} = TodoList.pop_events(list)

      assert {:error, _} = TodoList.complete_item(list, item.id)
      assert list.__pending_events__ == []
    end

    test "rename_item replaces the title inside the list" do
      item = item!()
      {:ok, list} = TodoList.add_item(list!(), item)
      assert {:ok, list} = TodoList.rename_item(list, item.id, title!("Buy oat milk"))
      assert [%{title: %{value: "Buy oat milk"}}] = list.items
    end

    test "an item that bypassed TodoItem is refused" do
      forged = %{item!() | status: :done}

      assert {:error, %Error{} = error} = TodoList.add_item(list!(), forged)
      assert error.code == :unsealed
      assert error.operation == :add_item
      assert error.details == %{struct: TodoItem}

      # Something that is not an item at all is refused by the type of the field.
      assert {:error, error} = TodoList.add_item(list!(), %{id: "x", title: %{value: "y"}})
      assert Error.codes(error) == [:invalid_type]
    end
  end
end

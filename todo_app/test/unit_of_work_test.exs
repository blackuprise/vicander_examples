defmodule TodoApp.UnitOfWorkTest do
  @moduledoc """
  What the framework's unit of work gives the commands of this application: a list is read
  once and written once, whatever the command does with it in between, and a list that does not
  exist stops the command before it starts.
  """
  use TodoApp.DataCase

  alias DDD.Error
  alias TodoApp.Application.Commands
  alias TodoApp.Infrastructure.TodoList.Repository, as: TodoListRepository

  setup do
    {:ok, user} = Commands.User.RegisterUser.call(%{name: "Ann", email: "ann@example.com"})
    {:ok, list} = Commands.TodoList.CreateList.call(%{owner_id: user.id, name: "Home"})
    %{user: user, list: list}
  end

  # The statements the repo runs while `fun` does.
  defp statements(fun) do
    parent = self()
    id = "statements-#{inspect(make_ref())}"

    :telemetry.attach(
      id,
      [:todo_app, :infrastructure, :repo, :query],
      fn _, _, %{query: query}, _ -> send(parent, {:statement, query}) end,
      nil
    )

    result = fun.()
    :telemetry.detach(id)
    {result, collect([])}
  end

  defp collect(acc) do
    receive do
      {:statement, query} -> collect([query | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp count(statements, text), do: Enum.count(statements, &(&1 =~ text))

  describe "a command that changes a list" do
    test "reads it once and writes it, with its event, in two statements", %{list: list} do
      {{:ok, _}, statements} =
        statements(fn ->
          Commands.TodoList.AddItem.call(%{list_id: list.id, title: "Buy milk"})
        end)

      # One read (`loads:` on `list_id`; the `find_by_id` in `execute/1` is answered from memory),
      # one UPDATE for the list, one INSERT for the `ItemAdded` event.
      assert count(statements, ~s(FROM "todo_lists")) == 1
      assert count(statements, ~s(UPDATE "todo_lists")) == 1
      assert count(statements, ~s(INSERT INTO "domain_events")) == 1
    end

    test "writes nothing when a rule refuses it", %{list: list} do
      {{:error, %Error{}}, statements} =
        statements(fn ->
          Commands.TodoList.AddItem.call(%{list_id: list.id, title: String.duplicate("a", 101)})
        end)

      assert count(statements, ~s(UPDATE "todo_lists")) == 0
      assert count(statements, ~s(INSERT INTO "domain_events")) == 0
    end

    test "sets updated_at when it writes the list, not when an operation runs", %{list: list} do
      Process.sleep(5)
      {:ok, updated} = Commands.TodoList.AddItem.call(%{list_id: list.id, title: "Buy milk"})

      assert DateTime.compare(updated.updated_at, list.updated_at) == :gt
      assert updated.created_at == list.created_at

      # What the command returned is what is stored.
      assert {:ok, ^updated} = TodoListRepository.find_by_id(list.id)
    end
  end

  describe "a list that does not exist" do
    test "stops every command that names one, before it does anything" do
      missing = DDD.Identity.generate()

      for {command, params} <- [
            {Commands.TodoList.AddItem, %{title: "x"}},
            {Commands.TodoList.CompleteItem, %{item_id: DDD.Identity.generate()}},
            {Commands.TodoList.RenameItem, %{item_id: DDD.Identity.generate(), title: "x"}}
          ] do
        {result, statements} =
          statements(fn -> command.call(Map.put(params, :list_id, missing)) end)

        assert {:error, %Error{code: :not_found, kind: :business} = error} = result
        assert error.entity == TodoApp.Domain.TodoList
        assert error.entity_id == missing
        assert error.details == %{field: :list_id, missing_ids: [missing]}
        assert error.context == %{command: command}

        # One read, which found nothing; no write.
        assert count(statements, ~s(UPDATE)) == 0
        assert count(statements, ~s(INSERT)) == 0
      end
    end
  end
end

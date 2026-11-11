defmodule TodoApp.ChainingTest do
  @moduledoc """
  Commands calling commands.

  A command that calls another joins its transaction and its unit of work, so a chain is written
  once, at the end, and either all of it happens or none. The one thing a chain cannot do is ask
  the repository a question that the database must answer (`find_by_owner_id`, `list`, `count`)
  after an earlier step has saved something: the database does not have that yet. Reading by id
  is always fine, because the unit of work holds what has been saved.
  """
  use TodoApp.DataCase

  import ExUnit.CaptureLog

  alias DDD.UnitOfWork.PendingChangesError
  alias TodoApp.Application.Commands
  alias TodoApp.Infrastructure.TodoList.Repository, as: TodoListRepository
  alias TodoApp.Infrastructure.User.Repository, as: UserRepository

  # A chain that cannot work: `RecordProgress` looks the user's lists up with `find_by_owner_id`,
  # and `CompleteItem` has just saved one of them.
  defmodule CompleteThenRecount do
    @moduledoc false
    use DDD.Command

    command do
      field :list_id, :uuid, required: true
      field :item_id, :uuid, required: true
      field :owner_id, :uuid, required: true
    end

    @impl DDD.Command
    def execute(%__MODULE__{list_id: list_id, item_id: item_id, owner_id: owner_id}) do
      with {:ok, _list} <-
             TodoApp.Application.Commands.TodoList.CompleteItem.call(%{
               list_id: list_id,
               item_id: item_id
             }),
           {:ok, user} <-
             TodoApp.Application.Commands.User.RecordProgress.call(%{owner_id: owner_id}) do
        {:ok, user}
      end
    end
  end

  # A chain that works, and then fails: nothing of it may stay.
  defmodule OnboardThenFail do
    @moduledoc false
    use DDD.Command

    command do
      field :email, :string, required: true
    end

    @impl DDD.Command
    def execute(%__MODULE__{email: email}) do
      with {:ok, _} <-
             TodoApp.Application.Commands.User.OnboardUser.call(%{name: "Ann", email: email}) do
        {:error, :changed_my_mind}
      end
    end
  end

  defp count(table), do: Repo.query!("SELECT count(*) FROM #{table}").rows |> hd() |> hd()

  # The statements the repo runs while `fun` does.
  defp statements(fun) do
    parent = self()
    id = "chain-#{inspect(make_ref())}"

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

  describe "a chain that only reads by id" do
    test "OnboardUser registers, creates a list and adds an item, written together" do
      {{:ok, %{user: user, list: list}}, statements} =
        statements(fn ->
          Commands.User.OnboardUser.call(%{name: "Ann", email: "ann@example.com"})
        end)

      # Each step found what the one before had saved, though none of it was in the database.
      assert list.owner_id == user.id
      assert [item] = list.items
      assert item.title.value == "Welcome to your list"

      # And it was written once, at the end: one INSERT per table, however many steps there were.
      assert Enum.count(statements, &(&1 =~ ~s(INSERT INTO "users"))) == 1
      assert Enum.count(statements, &(&1 =~ ~s(INSERT INTO "todo_lists"))) == 1
      assert Enum.count(statements, &(&1 =~ ~s(UPDATE))) == 0

      assert {:ok, ^user} = UserRepository.find_by_id(user.id)
      assert {:ok, ^list} = TodoListRepository.find_by_id(list.id)
    end

    test "a step that fails undoes the steps before it" do
      assert {:error, error} = Commands.User.OnboardUser.call(%{name: "Ann", email: "nope"})
      assert error.entity == TodoApp.Domain.User

      assert {count("users"), count("todo_lists"), count("domain_events")} == {0, 0, 0}
    end

    test "so does a failure after all the steps succeeded" do
      assert {:error, %DDD.Error{code: :changed_my_mind}} =
               OnboardThenFail.call(%{email: "ann@example.com"})

      assert {count("users"), count("todo_lists"), count("domain_events")} == {0, 0, 0}
    end
  end

  describe "a chain that asks a question after a save" do
    setup do
      {:ok, %{user: user, list: list}} =
        Commands.User.OnboardUser.call(%{name: "Ann", email: "ann@example.com"})

      %{user: user, list: list, item: hd(list.items)}
    end

    test "raises, and nothing of it stays", %{user: user, list: list, item: item} do
      log =
        capture_log(fn ->
          assert_raise PendingChangesError, ~r/find_by_owner_id.*unwritten changes/s, fn ->
            CompleteThenRecount.call(%{list_id: list.id, item_id: item.id, owner_id: user.id})
          end
        end)

      assert log =~ "crashed"

      # The completion that came first was rolled back with it.
      assert {:ok, stored} = TodoListRepository.find_by_id(list.id)
      assert Enum.all?(stored.items, &(&1.status != :done))
    end

    test "run the two one after the other instead: each is its own command", %{
      user: user,
      list: list,
      item: item
    } do
      assert {:ok, _} = Commands.TodoList.CompleteItem.call(%{list_id: list.id, item_id: item.id})

      # `CompleteItem` has committed, so the lists the database gives are up to date.
      assert {:ok, recorded} = Commands.User.RecordProgress.call(%{owner_id: user.id})
      assert recorded.completed_tasks == 1
    end
  end
end

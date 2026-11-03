defmodule TodoApp.AchievementsFlowTest do
  use TodoApp.DataCase

  import ExUnit.CaptureLog

  alias DDD.Error
  alias TodoApp.Application.Commands
  alias TodoApp.Application.Handlers.User.AchievementTracker
  alias TodoApp.Domain.TodoList.Events.ItemCompleted
  alias TodoApp.Domain.User.Achievement
  alias TodoApp.Domain.User.Events.AchievementEarned
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

  defp create_list!(user, name \\ "Home") do
    {:ok, list} = Commands.TodoList.CreateList.call(%{owner_id: user.id, name: name})
    list
  end

  # Add `n` items to the list and complete them all. Only one item is ever open at a time.
  defp complete_tasks!(list, n) do
    for i <- 1..n, n > 0 do
      {:ok, with_item} = Commands.TodoList.AddItem.call(%{list_id: list.id, title: "task #{i}"})
      item = List.last(with_item.items)
      {:ok, _} = Commands.TodoList.CompleteItem.call(%{list_id: list.id, item_id: item.id})
    end

    list
  end

  defp reload!(user) do
    {:ok, user} = UserRepository.find_by_id(user.id)
    user
  end

  defp codes(user), do: Enum.map(user.achievements, & &1.code)

  defp count_events(type),
    do:
      Repo.query!("SELECT count(*) FROM domain_events WHERE event_type = $1", [type]).rows
      |> hd()
      |> hd()

  defp wait_until(fun, attempts \\ 150) do
    cond do
      fun.() ->
        :ok

      attempts == 0 ->
        flunk("condition was not met in time")

      true ->
        Process.sleep(20)
        wait_until(fun, attempts - 1)
    end
  end

  describe "RecordProgress" do
    setup do
      user = register!()
      %{user: user, list: create_list!(user)}
    end

    test "a user who completed nothing has no achievements", %{user: user, list: list} do
      {:ok, _} = Commands.TodoList.AddItem.call(%{list_id: list.id, title: "open task"})

      assert {:ok, saved} = Commands.User.RecordProgress.call(%{owner_id: user.id})
      assert saved.completed_tasks == 0
      assert saved.achievements == []
    end

    test "the first completed task earns Newbie", %{user: user, list: list} do
      complete_tasks!(list, 1)

      assert {:ok, saved} = Commands.User.RecordProgress.call(%{owner_id: user.id})
      assert saved.completed_tasks == 1
      assert codes(saved) == [:newbie]
    end

    test "only completed items count, not open ones", %{user: user, list: list} do
      complete_tasks!(list, 2)
      {:ok, _} = Commands.TodoList.AddItem.call(%{list_id: list.id, title: "still open"})

      assert {:ok, %{completed_tasks: 2}} =
               Commands.User.RecordProgress.call(%{owner_id: user.id})
    end

    test "tasks are counted across all of the user's lists", %{user: user, list: list} do
      complete_tasks!(list, 4)
      complete_tasks!(create_list!(user, "Work"), 6)

      assert {:ok, saved} = Commands.User.RecordProgress.call(%{owner_id: user.id})
      assert saved.completed_tasks == 10
      assert codes(saved) == [:newbie, :beginner]
    end

    test "other users' tasks do not count", %{user: user, list: list} do
      complete_tasks!(list, 2)
      other = register!("bob@example.com")
      complete_tasks!(create_list!(other), 5)

      assert {:ok, %{completed_tasks: 2}} =
               Commands.User.RecordProgress.call(%{owner_id: user.id})
    end

    test "30 completed tasks earn Performer too", %{user: user, list: list} do
      complete_tasks!(list, 30)

      assert {:ok, saved} = Commands.User.RecordProgress.call(%{owner_id: user.id})
      assert codes(saved) == [:newbie, :beginner, :performer]
    end

    test "achievements are persisted and reload as sealed value objects", %{
      user: user,
      list: list
    } do
      complete_tasks!(list, 10)
      {:ok, saved} = Commands.User.RecordProgress.call(%{owner_id: user.id})

      reloaded = reload!(user)
      assert reloaded == saved

      assert [
               %Achievement{code: :newbie, awarded_at: %DateTime{}} = first,
               %Achievement{code: :beginner}
             ] = reloaded.achievements

      assert DDD.Schema.sealed?(first)
    end

    test "running it again changes nothing and announces nothing new", %{user: user, list: list} do
      complete_tasks!(list, 10)
      {:ok, first} = Commands.User.RecordProgress.call(%{owner_id: user.id})
      assert count_events("TodoApp.Domain.User.Events.AchievementEarned") == 2

      assert {:ok, second} = Commands.User.RecordProgress.call(%{owner_id: user.id})
      assert second.achievements == first.achievements
      assert count_events("TodoApp.Domain.User.Events.AchievementEarned") == 2
    end

    test "the earned achievements are announced with a link to the user", %{
      user: user,
      list: list
    } do
      complete_tasks!(list, 1)
      {:ok, _} = Commands.User.RecordProgress.call(%{owner_id: user.id})

      assert %{rows: [["TodoApp.Domain.User", id]]} =
               Repo.query!(
                 "SELECT aggregate_type, aggregate_id FROM domain_events WHERE event_type = 'TodoApp.Domain.User.Events.AchievementEarned'"
               )

      assert id == user.id
    end

    test "an unknown user is an error that names the command" do
      assert {:error,
              %Error{code: :user_not_found, context: %{command: Commands.User.RecordProgress}}} =
               Commands.User.RecordProgress.call(%{owner_id: UUID.uuid4()})
    end

    test "existing users saved before the columns existed load with defaults", %{user: user} do
      Repo.query!("UPDATE users SET completed_tasks = NULL, achievements = NULL WHERE id = $1", [
        Ecto.UUID.dump!(user.id)
      ])

      reloaded = reload!(user)
      assert reloaded.completed_tasks == 0
      assert reloaded.achievements == []
    end
  end

  describe "driven by events" do
    setup do
      :persistent_term.put({Forwarder, :pid}, self())
      DDD.EventBus.subscribe(AchievementEarned, Forwarder)
      AchievementTracker.subscribe()

      on_exit(fn ->
        AchievementTracker.unsubscribe()
        DDD.EventBus.unsubscribe(AchievementEarned, Forwarder)
      end)

      start_supervised!({DDD.Outbox.Poller, repo: Repo, interval_ms: 600_000})
      user = register!()
      %{user: user, list: create_list!(user)}
    end

    test "completing a task earns Newbie once the event is delivered", %{user: user, list: list} do
      complete_tasks!(list, 1)
      assert reload!(user).achievements == []

      # ItemAdded + ItemCompleted are in the outbox; delivering them triggers the tracker.
      {:ok, _} = DDD.Outbox.Poller.poll_now()
      wait_until(fn -> codes(reload!(user)) == [:newbie] end)

      # The tracker's own AchievementEarned event is delivered on the next poll.
      {:ok, _} = DDD.Outbox.Poller.poll_now()

      assert_receive {:event, %AchievementEarned{} = event}
      assert event.code == "newbie"
      assert event.aggregate_type == "TodoApp.Domain.User"
      assert event.aggregate_id == user.id
    end

    test "the handler can run for the same event twice without double counting", %{
      user: user,
      list: list
    } do
      complete_tasks!(list, 1)
      event = %ItemCompleted{aggregate_id: list.id}

      assert :ok = AchievementTracker.handle(event)
      assert :ok = AchievementTracker.handle(event)

      reloaded = reload!(user)
      assert reloaded.completed_tasks == 1
      assert codes(reloaded) == [:newbie]
    end

    test "an ItemCompleted for a list that does not exist is rejected: not retried, not a dead letter" do
      now = DateTime.utc_now()
      event_id = UUID.uuid4()

      Repo.insert_all("domain_events", [
        %{
          id: Ecto.UUID.dump!(event_id),
          event_type: "TodoApp.Domain.TodoList.Events.ItemCompleted",
          aggregate_id: UUID.uuid4(),
          aggregate_type: "TodoApp.Domain.TodoList",
          payload: %{"item_id" => UUID.uuid4()},
          occurred_at: now,
          inserted_at: now
        }
      ])

      log = capture_log(fn -> assert {:ok, 1} = DDD.Outbox.Poller.poll_now() end)
      assert log =~ "rejected"

      # Handled once and finished: published after a single attempt, remembered as rejected.
      assert %{rows: [[1, true, false]]} =
               Repo.query!(
                 "SELECT attempts, published_at IS NOT NULL, failed_at IS NOT NULL FROM domain_events WHERE id = $1",
                 [Ecto.UUID.dump!(event_id)]
               )

      assert %{
               rows: [
                 [
                   "TodoApp.Application.Handlers.User.AchievementTracker",
                   "rejected",
                   ":not_found"
                 ]
               ]
             } =
               Repo.query!("SELECT handler, outcome, reason FROM event_deliveries")

      assert {:ok, 0} = DDD.Outbox.Poller.poll_now()
      assert DDD.Outbox.DeadLetters.list(Repo, all: true) == []
    end

    test "an event for an unknown list is logged, not fatal" do
      log =
        capture_log(fn ->
          AchievementTracker.handle(%ItemCompleted{aggregate_id: UUID.uuid4()})
        end)

      assert log =~ "could not record progress"
    end
  end
end

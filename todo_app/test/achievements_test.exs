defmodule TodoApp.AchievementsTest do
  use ExUnit.Case, async: true

  alias DDD.Error
  alias TodoApp.Domain.User
  alias TodoApp.Domain.User.{Achievement, Achievements, Events}

  alias TodoApp.Domain.User.Specs.{
    AchievementsAreEarned,
    CompletedTasksAtLeast,
    NoDuplicateAchievements
  }

  defp user!(attrs \\ []) do
    {:ok, user} = User.new([name: "Ann", email: "ann@example.com"] ++ attrs)
    user
  end

  defp codes(user), do: Enum.map(user.achievements, & &1.code)

  defp events(user), do: Enum.map(user.__pending_events__, & &1.code)

  describe "the catalog" do
    test "has the three tiers, in order" do
      assert Achievements.codes() == [:newbie, :beginner, :performer]
      assert Achievements.get(:newbie).description == "Completed your first task"
      assert Achievements.get(:beginner).description == "Completed 10 tasks"
      assert Achievements.get(:performer).description == "Completed 30 tasks"
      assert Achievements.get(:unknown) == nil
    end

    test "earned_by/1 follows the thresholds: 1, 10 and 30 completed tasks" do
      earned = fn n -> Achievements.earned_by(%{completed_tasks: n}) end

      assert earned.(0) == []
      assert earned.(1) == [:newbie]
      assert earned.(9) == [:newbie]
      assert earned.(10) == [:newbie, :beginner]
      assert earned.(29) == [:newbie, :beginner]
      assert earned.(30) == [:newbie, :beginner, :performer]
      assert earned.(500) == [:newbie, :beginner, :performer]
    end
  end

  describe "CompletedTasksAtLeast" do
    test "reports how far the user is from the threshold" do
      assert :ok =
               DDD.Specification.evaluate({CompletedTasksAtLeast, min: 3}, %{completed_tasks: 3})

      assert {:error, violation} =
               DDD.Specification.evaluate({CompletedTasksAtLeast, min: 3}, %{completed_tasks: 2})

      assert violation.code == :not_enough_completed_tasks
      assert violation.field == :completed_tasks
      assert violation.details == %{min: 3, completed: 2}
    end
  end

  describe "Achievement value object" do
    test "needs a known code and an award time" do
      now = DateTime.utc_now()
      assert {:ok, %Achievement{code: :newbie}} = Achievement.new(code: :newbie, awarded_at: now)

      assert {:error, error} = Achievement.new(code: :legend, awarded_at: now)
      assert Error.to_map(error) == %{code: ["is not a known achievement"]}
      assert [%{code: :unknown_achievement, details: %{code: :legend}}] = error.violations

      assert {:error, error} = Achievement.new(code: :newbie)
      assert Error.codes(error) == [:required]
    end
  end

  describe "User.record_progress/2" do
    test "a new user has no progress" do
      user = user!()
      assert user.completed_tasks == 0
      assert user.achievements == []
    end

    test "no tasks earns nothing and emits nothing" do
      assert {:ok, user} = User.record_progress(user!(), 0)
      assert user.achievements == []
      assert user.__pending_events__ == []
    end

    test "the first task earns Newbie" do
      assert {:ok, user} = User.record_progress(user!(), 1)
      assert codes(user) == [:newbie]
      assert user.completed_tasks == 1
      assert [%Achievement{awarded_at: %DateTime{}}] = user.achievements
    end

    test "10 tasks earn Beginner as well, and 30 earn Performer" do
      {:ok, user} = User.record_progress(user!(), 10)
      assert codes(user) == [:newbie, :beginner]

      {:ok, user} = User.record_progress(user, 30)
      assert codes(user) == [:newbie, :beginner, :performer]
    end

    test "jumping straight to 30 awards all three at once" do
      {:ok, user} = User.record_progress(user!(), 30)
      assert codes(user) == [:newbie, :beginner, :performer]
      assert events(user) == ["newbie", "beginner", "performer"]
    end

    test "only the achievements not yet held are awarded and announced" do
      {:ok, user} = User.record_progress(user!(), 1)
      {_, user} = User.pop_events(user)

      {:ok, user} = User.record_progress(user, 10)
      assert codes(user) == [:newbie, :beginner]
      assert events(user) == ["beginner"]
    end

    test "events are linked to the user" do
      user = user!()
      {:ok, user} = User.record_progress(user, 1)
      assert [%Events.AchievementEarned{} = event] = user.__pending_events__

      assert event.code == "newbie"
      assert event.aggregate_type == "TodoApp.Domain.User"
      assert event.aggregate_id == user.id
    end

    test "repeating the same count changes nothing (safe to redeliver)" do
      {:ok, once} = User.record_progress(user!(), 10)
      {_, once} = User.pop_events(once)
      {:ok, twice} = User.record_progress(once, 10)

      assert twice.achievements == once.achievements
      assert twice.__pending_events__ == []
    end

    test "the count never goes down, and achievements are never taken back" do
      {:ok, user} = User.record_progress(user!(), 10)
      {:ok, user} = User.record_progress(user, 3)
      assert user.completed_tasks == 10
      assert codes(user) == [:newbie, :beginner]
    end

    test "only integers are accepted" do
      assert {:error, %Error{code: :invalid_operation, operation: :record_progress}} =
               User.record_progress(user!(), "ten")
    end
  end

  describe "invariants" do
    test "a user cannot hold an achievement twice" do
      {:ok, user} = User.record_progress(user!(), 1)
      [newbie] = user.achievements

      assert {:error, error} = User.update(user, achievements: [newbie, newbie])

      assert [%{field: :achievements, code: :duplicate_achievement, details: %{codes: [:newbie]}}] =
               error.violations
    end

    test "a user cannot hold an achievement they have not earned" do
      {:ok, newbie} = Achievement.new(code: :newbie, awarded_at: DateTime.utc_now())

      assert {:error, error} = User.update(user!(), achievements: [newbie])
      assert [%{code: :achievement_not_earned, details: %{codes: [:newbie]}}] = error.violations

      assert {:error, error} =
               User.new(name: "Bob", email: "bob@example.com", achievements: [newbie])

      assert Error.has_code?(error, :achievement_not_earned)
    end

    test "progress cannot be negative" do
      assert {:error, error} = User.update(user!(), completed_tasks: -1)
      assert Error.to_map(error) == %{completed_tasks: ["cannot be negative"]}
    end

    test "the specs can be used on their own" do
      assert NoDuplicateAchievements.satisfied_by?(%{achievements: []}, on: :achievements)

      refute AchievementsAreEarned.satisfied_by?(%{
               achievements: [%{code: :newbie}],
               completed_tasks: 0
             })

      assert AchievementsAreEarned.satisfied_by?(%{
               achievements: [%{code: :newbie}],
               completed_tasks: 1
             })
    end
  end
end

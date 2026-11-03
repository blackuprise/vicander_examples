defmodule TodoApp.FieldSpecsTest do
  use ExUnit.Case, async: true

  alias DDD.Error
  alias DDD.Specification
  alias TodoApp.Domain.{TodoList, User}
  alias TodoApp.Domain.TodoList.{Title, TodoItem}
  alias TodoApp.Domain.TodoList.Specs.{ListNameNotBlank, TitleWithinLimit}
  alias TodoApp.Domain.User.Specs.{NonNegativeProgress, ValidEmail}

  defp title!(value) do
    {:ok, title} = Title.new(value: value)
    title
  end

  describe "TitleWithinLimit" do
    test "allows exactly the maximum and reports the length beyond it" do
      assert :ok =
               Specification.evaluate({TitleWithinLimit, on: :value, max: 5}, %{value: "12345"})

      assert {:error, violation} =
               Specification.evaluate({TitleWithinLimit, on: :value, max: 5}, %{value: "123456"})

      assert %{field: :value, code: :title_too_long, message: "must be at most 5 characters"} =
               violation

      assert violation.details == %{max: 5, length: 6}
    end

    test "defaults to 100 characters and counts graphemes, not bytes" do
      assert :ok =
               Specification.evaluate({TitleWithinLimit, on: :value}, %{
                 value: String.duplicate("é", 100)
               })

      assert {:error, _} =
               Specification.evaluate({TitleWithinLimit, on: :value}, %{
                 value: String.duplicate("a", 101)
               })
    end

    test "has nothing to say about a missing value (presence is a field rule)" do
      assert :ok = Specification.evaluate({TitleWithinLimit, on: :value}, %{value: nil})
    end
  end

  describe "ValidEmail" do
    test "accepts addresses" do
      for email <- ["ann@example.com", "a.b+c@sub.example.org"] do
        assert ValidEmail.satisfied_by?(%{email: email}, on: :email), email
      end
    end

    test "rejects things that are not addresses" do
      for email <- [
            "nope",
            "no at.com",
            "a@b",
            "a b@example.com",
            "@example.com",
            "a@@example.com"
          ] do
        assert {:error,
                %{field: :email, code: :invalid_email, message: "must be a valid email address"}} =
                 Specification.evaluate({ValidEmail, on: :email}, %{email: email})
      end
    end

    test "ignores a missing email" do
      assert ValidEmail.satisfied_by?(%{email: nil}, on: :email)
    end
  end

  describe "NonNegativeProgress" do
    test "rejects a negative count, with the value" do
      assert {:error, violation} =
               Specification.evaluate({NonNegativeProgress, on: :completed_tasks}, %{
                 completed_tasks: -3
               })

      assert %{field: :completed_tasks, code: :negative_progress, message: "cannot be negative"} =
               violation

      assert violation.details == %{completed_tasks: -3}
    end

    test "accepts zero, positive numbers and a missing value" do
      for value <- [0, 7, nil] do
        assert NonNegativeProgress.satisfied_by?(%{completed_tasks: value}, on: :completed_tasks)
      end
    end
  end

  describe "ListNameNotBlank" do
    test "rejects empty and whitespace-only names" do
      for name <- ["", "   ", "\t\n"] do
        assert {:error, %{field: :name, code: :name_blank, message: "must not be blank"}} =
                 Specification.evaluate({ListNameNotBlank, on: :name}, %{name: name})
      end
    end

    test "accepts a name and ignores a missing one" do
      assert ListNameNotBlank.satisfied_by?(%{name: "Home"}, on: :name)
      assert ListNameNotBlank.satisfied_by?(%{name: nil}, on: :name)
    end
  end

  describe "enforced on the domain objects, reported under the field with a specific code" do
    test "Title" do
      assert {:error, error} = Title.new(value: String.duplicate("a", 101))
      assert [%{field: :value, code: :title_too_long}] = error.violations
      assert Error.to_map(error) == %{value: ["must be at most 100 characters"]}
    end

    test "User" do
      assert {:error, error} = User.new(name: "Ann", email: "nope")
      assert [%{field: :email, code: :invalid_email}] = error.violations

      {:ok, user} = User.new(name: "Ann", email: "ann@example.com")
      assert {:error, error} = User.update(user, completed_tasks: -1)
      assert [%{field: :completed_tasks, code: :negative_progress}] = error.violations
    end

    test "TodoItem" do
      assert {:error, error} = TodoItem.new(title: title!("x"), status: :weird)
      assert [%{field: :status, code: :invalid_type}] = error.violations
    end

    test "TodoList" do
      assert {:error, error} = TodoList.new(owner_id: UUID.uuid4(), name: "   ")
      assert [%{field: :name, code: :name_blank}] = error.violations
    end
  end

  describe "all rules are reported at once" do
    test "a todo item with several broken rules lists every violation" do
      yesterday = Date.add(Date.utc_today(), -1)

      assert {:error, error} =
               TodoItem.new(title: title!("   "), due_date: yesterday)

      assert Enum.sort(Error.codes(error)) == [:due_date_in_past, :title_blank]
    end

    test "a user with a bad email and negative progress gets both" do
      assert {:error, error} = User.new(name: "Ann", email: "nope", completed_tasks: -1)
      assert Enum.sort(Error.codes(error)) == [:invalid_email, :negative_progress]
    end

    test "required fields still come first: nothing else is checked until they are present" do
      assert {:error, error} = User.new(name: "Ann", completed_tasks: -1)
      assert Error.codes(error) == [:required]
    end
  end

  describe "value specs are bound to a field" do
    test "the same spec checks whichever field it is attached to" do
      assert {:error, %{field: :billing_email, code: :invalid_email}} =
               Specification.evaluate({ValidEmail, on: :billing_email}, %{
                 email: "ok@example.com",
                 billing_email: "nope"
               })
    end

    test "using one without `on:` or on a missing field is an error, not a silent pass" do
      assert_raise ArgumentError, ~r/attach it with `on: :field`/, fn ->
        Specification.evaluate(ValidEmail, %{email: "nope"})
      end

      assert_raise ArgumentError, ~r/no field :mail/, fn ->
        Specification.evaluate({ValidEmail, on: :mail}, %{email: "nope"})
      end
    end

    test "attaching one to a field the entity doesn't have fails to compile" do
      assert_raise CompileError, ~r/has no such field/, fn ->
        Code.compile_string("""
        defmodule TodoApp.FieldSpecsTest.WrongField do
          use DDD.ValueObject

          value_object do
            field :email, :string
            invariant TodoApp.Domain.User.Specs.ValidEmail, on: :mail
          end
        end
        """)
      end
    end

    test "forgetting `on:` fails to compile, also inside a composite" do
      for invariant <- [
            "invariant TodoApp.Domain.User.Specs.ValidEmail",
            "invariant DDD.Specification.all_of([TodoApp.Domain.User.Specs.ValidEmail])"
          ] do
        assert_raise CompileError, ~r/add `on: :field`/, fn ->
          Code.compile_string("""
          defmodule TodoApp.FieldSpecsTest.NoOn do
            use DDD.ValueObject

            value_object do
              field :email, :string
              #{invariant}
            end
          end
          """)
        end
      end
    end

    test "composites, negation and per-spec options reach the value specs" do
      alias TodoApp.Domain.User.Specs.NonNegativeProgress

      assert {:error, _} =
               Specification.evaluate(
                 Specification.not_spec({NonNegativeProgress, on: :n}),
                 %{n: 1}
               )

      assert :ok =
               Specification.evaluate(
                 Specification.any_of([{ValidEmail, on: :a}, {ValidEmail, on: :b}]),
                 %{a: "x", b: "y@z.io"}
               )

      assert :ok =
               Specification.evaluate(
                 Specification.all_of([{ValidEmail, on: :a}]),
                 %{a: "x@y.io"}
               )
    end

    test "an unknown scope is refused" do
      assert_raise ArgumentError, ~r/scope must be/, fn ->
        Code.compile_string("""
        defmodule TodoApp.FieldSpecsTest.BadScope do
          use DDD.Specification, scope: :nope
        end
        """)
      end
    end
  end
end

defmodule TodoApp.Domain.User.Specs.NoDuplicateAchievements do
  @moduledoc "A user holds each achievement at most once. A value spec (`on: :achievements`)."
  use DDD.Specification, scope: :value

  @impl DDD.Specification
  def check(achievements, _opts) do
    codes = Enum.map(achievements, & &1.code)

    case codes -- Enum.uniq(codes) do
      [] ->
        :ok

      duplicates ->
        {:error, :duplicate_achievement, "achievement held twice",
         %{codes: Enum.uniq(duplicates)}}
    end
  end
end

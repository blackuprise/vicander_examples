defmodule TodoApp.Domain.User.Specs.KnownAchievement do
  @moduledoc "An achievement's code must be one the catalog defines. A value spec (`on: :code`)."
  use DDD.Specification, scope: :value

  @impl DDD.Specification
  def check(code, _opts) do
    if code in TodoApp.Domain.User.Achievements.codes(),
      do: :ok,
      else: {:error, :unknown_achievement, "is not a known achievement", %{code: code}}
  end
end

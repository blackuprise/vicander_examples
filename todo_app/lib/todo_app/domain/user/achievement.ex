defmodule TodoApp.Domain.User.Achievement do
  @moduledoc "Value object: an achievement a user holds, and when it was awarded."
  use DDD.ValueObject

  value_object do
    field :code, :atom, required: true
    field :awarded_at, :datetime_usec, required: true

    invariant TodoApp.Domain.User.Specs.KnownAchievement, on: :code
  end
end

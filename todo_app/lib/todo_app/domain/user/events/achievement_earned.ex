defmodule TodoApp.Domain.User.Events.AchievementEarned do
  @moduledoc false
  use DDD.DomainEvent

  domain_event do
    field :code, :string
  end
end

defmodule TodoApp.Domain.TodoList.Events.ItemCompleted do
  @moduledoc false
  use DDD.DomainEvent

  domain_event do
    field :item_id, :string
  end
end

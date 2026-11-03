defmodule TodoApp.Domain.TodoList.Events.ItemAdded do
  @moduledoc false
  use DDD.DomainEvent

  domain_event do
    field :item_id, :string
    field :title, :string
  end
end

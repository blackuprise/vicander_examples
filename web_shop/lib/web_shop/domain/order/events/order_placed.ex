defmodule WebShop.Domain.Order.Events.OrderPlaced do
  @moduledoc "An order was placed. `day` (ISO date, UTC) is what the daily sales report groups by."
  use DDD.DomainEvent

  domain_event do
    field :customer_id, :string
    field :total_cents, :integer
    field :items, :integer
    field :day, :string
  end
end

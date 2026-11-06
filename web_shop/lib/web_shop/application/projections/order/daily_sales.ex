defmodule WebShop.Application.Projections.Order.DailySales do
  @moduledoc """
  A read model: one row per day with the orders placed, the units sold and the revenue.
  Fed by `OrderPlaced` through the outbox, so it trails the orders by a moment. The row is keyed
  by the event's `day` (an ISO date, UTC).
  """
  alias WebShop.Domain.Order.Events.OrderPlaced

  use DDD.Projection, table: "daily_sales", key: :day, key_from: :day, events: [OrderPlaced]

  projection do
    description "Per day (UTC): orders placed, units sold and revenue in cents"
    field :day, :string
    field :orders, :integer, default: 0
    field :items_sold, :integer, default: 0
    field :revenue_cents, :integer, default: 0
  end

  on %OrderPlaced{} = event,
    do: {:inc, orders: 1, items_sold: event.items, revenue_cents: event.total_cents}
end

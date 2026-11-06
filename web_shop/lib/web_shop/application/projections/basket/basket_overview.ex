defmodule WebShop.Application.Projections.Basket.BasketOverview do
  @moduledoc """
  A read model: one row per basket with what is in it now. A basket with `item_count > 0` is a
  *pending* basket: someone has picked things and not checked out. Fed by the basket's events,
  all of them increments, so the order they arrive in does not matter.
  """
  alias WebShop.Domain.Basket.Events.{CheckedOut, ItemAdded, ItemRemoved}

  use DDD.Projection,
    table: "basket_overviews",
    key: :basket_id,
    events: [ItemAdded, ItemRemoved, CheckedOut]

  projection do
    description "Per basket: the owner, units inside and their value in cents"
    field :basket_id, :uuid
    field :customer_id, :uuid
    field :item_count, :integer, default: 0
    field :total_cents, :integer, default: 0
  end

  on %ItemAdded{} = event,
    do: [
      {:upsert, %{customer_id: event.customer_id}},
      {:inc, item_count: event.quantity, total_cents: event.amount_cents}
    ]

  on %ItemRemoved{} = event,
    do: {:inc, item_count: -event.quantity, total_cents: -event.amount_cents}

  on %CheckedOut{} = event,
    do: {:inc, item_count: -event.quantity, total_cents: -event.amount_cents}
end

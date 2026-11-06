defmodule WebShop.Domain.Basket.Events.ItemRemoved do
  @moduledoc "A basket changed: how many units and how many cents were added/removed."
  use DDD.DomainEvent

  domain_event do
    field :customer_id, :string
    field :quantity, :integer
    field :amount_cents, :integer
  end
end

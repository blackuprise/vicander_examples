defmodule WebShop.Domain do
  @moduledoc """
  The domain layer: aggregates, entities, value objects, specifications, events and the
  repository ports. It knows only the `DDD` framework.
  """
  use Boundary,
    top_level?: true,
    deps: [],
    check: [apps: [:ecto, :ecto_sql, :postgrex]],
    exports: [
      User,
      User.Password,
      User.Repository,
      Product,
      Product.Repository,
      Basket,
      Basket.BasketItem,
      Basket.Repository,
      Order,
      Order.OrderLine,
      Order.Repository,
      Basket.Events.ItemAdded,
      Basket.Events.ItemRemoved,
      Basket.Events.CheckedOut,
      Order.Events.OrderPlaced
    ]
end

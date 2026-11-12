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
      OAuth.Client,
      OAuth.Client.Repository,
      OAuth.Client.Specs.RedirectUrisAllowed,
      OAuth.Grant,
      OAuth.Grant.Repository,
      OAuth.Scopes,
      OAuth.Secret,
      OAuth.Settings,
      OAuth.TokenSigner,
      OAuth.TokenVerifier,
      Basket.Events.ItemAdded,
      Basket.Events.ItemRemoved,
      Basket.Events.CheckedOut,
      Order.Events.OrderPlaced
    ]
end

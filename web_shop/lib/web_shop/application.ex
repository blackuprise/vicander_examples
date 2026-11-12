defmodule WebShop.Application do
  @moduledoc """
  The application layer: commands, queries and the projections (read models) the reports read.
  It orchestrates the domain through its ports and never touches infrastructure.
  """
  use Boundary,
    top_level?: true,
    deps: [WebShop.Domain],
    exports: [
      Commands.User.RegisterUser,
      Commands.Product.AddProduct,
      Commands.Product.RestockProduct,
      Commands.Basket.AddToBasket,
      Commands.Basket.RemoveFromBasket,
      Commands.Basket.CheckOut,
      Queries.User.Authenticate,
      Queries.User.GetUser,
      Queries.Product.ListProducts,
      Queries.Basket.ViewBasket,
      Queries.Basket.PendingBaskets,
      Queries.Order.OrdersOfCustomer,
      Queries.Report.ShopReport,
      Commands.OAuth.RegisterClient,
      Commands.OAuth.AuthorizeClient,
      Commands.OAuth.ExchangeCode,
      Commands.OAuth.RefreshGrant,
      Queries.OAuth.GetClient,
      Queries.OAuth.AuthenticateToken,
      Queries.OAuth.ResourceMetadata,
      Queries.OAuth.ServerMetadata,
      Queries.OAuth.Jwks,
      OAuth.Endpoints,
      OAuth.Access,
      Projections.Order.DailySales,
      Projections.Basket.BasketOverview
    ]
end

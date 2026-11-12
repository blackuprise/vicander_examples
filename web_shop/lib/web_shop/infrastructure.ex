defmodule WebShop.Infrastructure do
  @moduledoc "The infrastructure layer: Postgres adapters for the domain's ports."
  use Boundary,
    top_level?: true,
    deps: [WebShop.Domain],
    exports: [
      Repo,
      User.Repository,
      Product.Repository,
      Basket.Repository,
      Order.Repository,
      OAuth.Client.Repository,
      OAuth.Grant.Repository,
      OAuth.JoseSigner,
      OAuth.BuiltinVerifier,
      OAuth.ExternalVerifier,
      OAuth.Keys
    ]
end

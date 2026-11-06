defmodule WebShop.Infrastructure do
  @moduledoc "The infrastructure layer: Postgres adapters for the domain's ports."
  use Boundary,
    top_level?: true,
    deps: [WebShop.Domain],
    exports: [
      Repo,
      LogRedactor,
      User.Repository,
      Product.Repository,
      Basket.Repository,
      Order.Repository
    ]
end

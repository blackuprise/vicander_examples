defmodule WebShop.Infrastructure.Product.Repository do
  @moduledoc "Postgres adapter for `WebShop.Domain.Product.Repository`."
  use DDD.Repository.Ecto,
    port: WebShop.Domain.Product.Repository,
    repo: WebShop.Infrastructure.Repo,
    table: "products"
end

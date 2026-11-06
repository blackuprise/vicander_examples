defmodule WebShop.Infrastructure.Basket.Repository do
  @moduledoc "Postgres adapter for `WebShop.Domain.Basket.Repository`."
  use DDD.Repository.Ecto,
    port: WebShop.Domain.Basket.Repository,
    repo: WebShop.Infrastructure.Repo,
    table: "baskets"
end

defmodule WebShop.Infrastructure.Order.Repository do
  @moduledoc "Postgres adapter for `WebShop.Domain.Order.Repository`."
  use DDD.Repository.Ecto,
    port: WebShop.Domain.Order.Repository,
    repo: WebShop.Infrastructure.Repo,
    table: "orders"
end

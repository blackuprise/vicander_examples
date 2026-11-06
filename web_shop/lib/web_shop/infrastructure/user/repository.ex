defmodule WebShop.Infrastructure.User.Repository do
  @moduledoc "Postgres adapter for `WebShop.Domain.User.Repository`."
  use DDD.Repository.Ecto,
    port: WebShop.Domain.User.Repository,
    repo: WebShop.Infrastructure.Repo,
    table: "users"
end

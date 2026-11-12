defmodule WebShop.Infrastructure.OAuth.Grant.Repository do
  @moduledoc "Postgres adapter for `WebShop.Domain.OAuth.Grant.Repository`."
  use DDD.Repository.Ecto,
    port: WebShop.Domain.OAuth.Grant.Repository,
    repo: WebShop.Infrastructure.Repo,
    table: "oauth_grants"
end

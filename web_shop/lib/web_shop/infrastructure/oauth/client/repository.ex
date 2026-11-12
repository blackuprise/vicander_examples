defmodule WebShop.Infrastructure.OAuth.Client.Repository do
  @moduledoc "Postgres adapter for `WebShop.Domain.OAuth.Client.Repository`."
  use DDD.Repository.Ecto,
    port: WebShop.Domain.OAuth.Client.Repository,
    repo: WebShop.Infrastructure.Repo,
    table: "oauth_clients"
end

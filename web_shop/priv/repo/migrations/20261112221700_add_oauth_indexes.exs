defmodule WebShop.Infrastructure.Repo.Migrations.AddOauthIndexes do
  use Ecto.Migration

  # A grant is found by the hash of the secret an app presents, so those columns are indexed, and a
  # secret belongs to one grant. (A NULL hash, an unused or spent secret, is not a duplicate.)
  def change do
    create unique_index(:oauth_grants, [:code_hash])
    create unique_index(:oauth_grants, [:refresh_hash])
    create index(:oauth_grants, [:previous_refresh_hash])
    create index(:oauth_grants, [:user_id])
  end
end

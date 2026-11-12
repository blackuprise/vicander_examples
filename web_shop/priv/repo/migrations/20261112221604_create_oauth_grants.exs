defmodule WebShop.Infrastructure.Repo.Migrations.CreateOauthGrants do
  use Ecto.Migration

  def change do
    create table(:oauth_grants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :client_id, :string, null: false
      add :user_id, :binary_id, null: false
      add :scopes, {:array, :string}, null: false
      add :redirect_uri, :string, null: false
      add :code_challenge, :string, null: false
      add :code_hash, :string
      add :code_expires_at, :utc_datetime
      add :code_used_at, :utc_datetime
      add :refresh_hash, :string
      add :previous_refresh_hash, :string
      add :refresh_expires_at, :utc_datetime
      add :last_used_at, :utc_datetime
      add :revoked_at, :utc_datetime
      add :created_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
      add :version, :integer, null: false, default: 0
    end
  end
end

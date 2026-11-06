defmodule WebShop.Infrastructure.Repo.Migrations.CreateBaskets do
  use Ecto.Migration

  def change do
    create table(:baskets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :customer_id, :binary_id
      add :items, :map
      add :created_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
      add :version, :integer, null: false, default: 0
    end
  end
end

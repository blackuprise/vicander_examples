defmodule WebShop.Infrastructure.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :description, :string
      add :price_cents, :integer
      add :stock, :integer
      add :created_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
      add :version, :integer, null: false, default: 0
    end
  end
end

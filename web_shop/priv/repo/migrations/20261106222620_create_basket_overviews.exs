defmodule WebShop.Infrastructure.Repo.Migrations.CreateBasketOverviews do
  use Ecto.Migration

  def change do
    create table(:basket_overviews, primary_key: false) do
      add :basket_id, :binary_id, primary_key: true
      add :customer_id, :binary_id
      add :item_count, :integer
      add :total_cents, :integer
    end
  end
end

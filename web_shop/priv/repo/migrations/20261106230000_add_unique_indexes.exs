defmodule WebShop.Infrastructure.Repo.Migrations.AddUniqueIndexes do
  use Ecto.Migration

  # The commands check these first; the indexes make them hold when two requests race.
  def change do
    create unique_index(:users, [:email])
    create unique_index(:baskets, [:customer_id])
    create index(:orders, [:customer_id])
  end
end

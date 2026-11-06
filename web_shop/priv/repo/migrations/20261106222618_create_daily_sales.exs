defmodule WebShop.Infrastructure.Repo.Migrations.CreateDailySales do
  use Ecto.Migration

  def change do
    create table(:daily_sales, primary_key: false) do
      add :day, :string, primary_key: true
      add :orders, :integer
      add :items_sold, :integer
      add :revenue_cents, :integer
    end
  end
end

defmodule TodoApp.Infrastructure.Repo.Migrations.AlterUsers20261031215807 do
  use Ecto.Migration

  def change do
    rename table(:users), :inserted_at, to: :created_at
  end
end

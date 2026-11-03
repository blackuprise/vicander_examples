defmodule TodoApp.Infrastructure.Repo.Migrations.AlterUsers20261101122146 do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :version, :integer, null: false, default: 0
    end
  end
end

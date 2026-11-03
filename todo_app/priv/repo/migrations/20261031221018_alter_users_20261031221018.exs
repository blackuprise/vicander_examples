defmodule TodoApp.Infrastructure.Repo.Migrations.AlterUsers20261031221018 do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :completed_tasks, :integer
      add :achievements, {:array, :map}
    end
  end
end

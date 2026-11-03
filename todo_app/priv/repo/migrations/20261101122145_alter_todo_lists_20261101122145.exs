defmodule TodoApp.Infrastructure.Repo.Migrations.AlterTodoLists20261101122145 do
  use Ecto.Migration

  def change do
    alter table(:todo_lists) do
      add :version, :integer, null: false, default: 0
    end
  end
end

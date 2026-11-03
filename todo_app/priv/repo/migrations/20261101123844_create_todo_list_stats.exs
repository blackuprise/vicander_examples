defmodule TodoApp.Infrastructure.Repo.Migrations.CreateTodoListStats do
  use Ecto.Migration

  def change do
    create table(:todo_list_stats, primary_key: false) do
      add :list_id, :binary_id, primary_key: true
      add :items_added, :integer
      add :items_completed, :integer
      add :last_activity_at, :utc_datetime_usec
    end
  end
end

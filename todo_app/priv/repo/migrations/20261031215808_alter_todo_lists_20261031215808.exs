defmodule TodoApp.Infrastructure.Repo.Migrations.AlterTodoLists20261031215808 do
  use Ecto.Migration

  def change do
    rename table(:todo_lists), :inserted_at, to: :created_at
  end
end

defmodule TodoApp.Infrastructure.Repo.Migrations.StoreNestedListsAsOneJsonColumn do
  use Ecto.Migration

  # The framework now stores a list of nested entities (`{:list, Item}`) as one `jsonb` array
  # instead of a Postgres array of `jsonb` (`jsonb[]`). The data is converted in place.
  @columns [{"todo_lists", "items"}, {"users", "achievements"}]

  def up do
    for {table, column} <- @columns do
      execute "ALTER TABLE #{table} ALTER COLUMN #{column} TYPE jsonb USING to_jsonb(#{column})"
    end
  end

  # `ALTER ... USING` can't contain a subquery, so each column is rebuilt through a new one.
  def down do
    for {table, column} <- @columns do
      execute "ALTER TABLE #{table} ADD COLUMN #{column}_old jsonb[]"
      execute "UPDATE #{table} SET #{column}_old = ARRAY(SELECT jsonb_array_elements(#{column}))"
      execute "ALTER TABLE #{table} DROP COLUMN #{column}"
      execute "ALTER TABLE #{table} RENAME COLUMN #{column}_old TO #{column}"
    end
  end
end

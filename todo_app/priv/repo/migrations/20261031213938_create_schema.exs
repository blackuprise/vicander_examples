defmodule TodoApp.Infrastructure.Repo.Migrations.CreateSchema do
  use Ecto.Migration

  def change do
    # --- Outbox -------------------------------------------------------------------------

    create table(:domain_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_type, :string, null: false
      add :aggregate_id, :string, null: false
      add :aggregate_type, :string, null: false
      add :payload, :map, null: false
      add :occurred_at, :utc_datetime_usec, null: false
      add :published_at, :utc_datetime_usec, null: true

      # Retry bookkeeping: delivery attempts, the last failure, when to retry, and the
      # lease that keeps two pollers from taking the same event.
      add :attempts, :integer, null: false, default: 0
      add :last_error, :text
      add :next_attempt_at, :utc_datetime_usec
      add :locked_until, :utc_datetime_usec
      # Set after too many failed attempts (dead letter): the event is no longer claimed.
      add :failed_at, :utc_datetime_usec

      # What happened to a dead letter: "kept" (acknowledged and left as is), "discarded".
      # A replay clears the failure state instead, and counts in `replays`.
      add :resolution, :string
      add :resolved_at, :utc_datetime_usec
      add :replays, :integer, null: false, default: 0

      timestamps(updated_at: false)
    end

    create index(:domain_events, [:published_at])
    create index(:domain_events, [:aggregate_id])
    create index(:domain_events, [:aggregate_type])
    create index(:domain_events, [:occurred_at])

    create index(:domain_events, [:occurred_at],
             where: "published_at IS NULL AND failed_at IS NULL",
             name: :domain_events_pending_index
           )

    create index(:domain_events, [:failed_at],
             where: "failed_at IS NOT NULL AND resolved_at IS NULL",
             name: :domain_events_unresolved_dead_letters_index
           )

    # Which handler already processed which event, so a retry skips the handlers that
    # succeeded and only re-runs the ones that failed.
    create table(:event_deliveries, primary_key: false) do
      add :event_id, references(:domain_events, type: :binary_id, on_delete: :delete_all),
        null: false

      add :handler, :string, null: false
      add :delivered_at, :utc_datetime_usec, null: false

      # "delivered", or "rejected" when the handler answered with a business error. A
      # rejection is remembered so the handler is not run again for that event.
      add :outcome, :string, null: false, default: "delivered"
      add :reason, :text
    end

    create unique_index(:event_deliveries, [:event_id, :handler])

    # --- Aggregates ---------------------------------------------------------------------

    # A list of nested entities is stored as one `jsonb` array (not a `jsonb[]`).
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :email, :string
      add :completed_tasks, :integer
      add :achievements, :jsonb
      add :version, :integer, null: false, default: 0
      add :created_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create table(:todo_lists, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :owner_id, :binary_id
      add :name, :string
      add :items, :jsonb
      add :version, :integer, null: false, default: 0
      add :created_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    # --- Read models --------------------------------------------------------------------

    create table(:todo_list_stats, primary_key: false) do
      add :list_id, :binary_id, primary_key: true
      add :items_added, :integer
      add :items_completed, :integer
      add :last_activity_at, :utc_datetime_usec
    end
  end
end

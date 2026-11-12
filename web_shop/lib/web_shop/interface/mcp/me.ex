defmodule WebShop.Interface.MCP.Me do
  @moduledoc """
  The user the MCP server acts as. The other tools take ids (`customer_id`, `admin_id`), and an
  AI client has no other way to learn its own.
  """
  use DDD.Query, transaction: false

  alias WebShop.Interface.MCP.Policy

  query do
    description "Who you are signed in as: your id, name, email and role. Call this first: " <>
                  "the other tools take your id"
  end

  @impl DDD.Query
  def execute(%__MODULE__{}) do
    case Policy.current_user() do
      {:ok, user} -> {:ok, Map.take(user, [:id, :name, :email, :role])}
      {:error, reason} -> {:error, {:not_signed_in, reason}}
    end
  end
end

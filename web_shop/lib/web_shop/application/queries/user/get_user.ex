defmodule WebShop.Application.Queries.User.GetUser do
  @moduledoc "A user by id, without the password hash. The web session stores only the id."
  use DDD.Query

  alias WebShop.Domain.User.Repository, as: UserRepository

  query do
    description "A user's id, name, email and role"

    field :id, :uuid, required: true, description: "The id of the user"
  end

  @impl DDD.Query
  def execute(%__MODULE__{id: id}) do
    case UserRepository.impl().find_by_id(id) do
      {:ok, user} -> {:ok, summary(user)}
      {:error, :not_found} -> {:error, {:user_not_found, "user #{id} does not exist"}}
    end
  end

  @doc false
  def summary(user), do: Map.take(user, [:id, :name, :email, :role])
end

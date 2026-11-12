defmodule WebShop.Application.Queries.OAuth.AuthenticateToken do
  @moduledoc """
  Who is behind an access token, as far as the MCP endpoint is concerned: the verified token
  (see `WebShop.Domain.OAuth.TokenVerifier`) mapped to a shop user.

  A token the shop issued names the user by id; an external server's names a person by a
  verified email, and there must be a shop account with it (none is created). The user is read
  now, so a deleted account is refused; the **role is the account's, never the token's**, and is
  returned here so the caller reads it from the database and not from anything it was handed.
  """
  use DDD.Query, transaction: false

  alias WebShop.Domain.OAuth.TokenVerifier
  alias WebShop.Domain.User.Repository, as: UserRepository

  query do
    description "The shop user and the scopes behind an access token"

    field :token, :string, required: true, sensitive: true, description: "The access token"
  end

  @impl DDD.Query
  def execute(%__MODULE__{token: token}) do
    with {:ok, claims} <- TokenVerifier.impl().verify(token),
         {:ok, user} <- find_user(claims.subject) do
      {:ok,
       %{
         user_id: user.id,
         role: user.role,
         scopes: claims.scopes,
         client_id: claims.client_id
       }}
    end
  end

  defp find_user({:user_id, id}) do
    with {:ok, _} <- Ecto.UUID.cast(id),
         {:ok, user} <- UserRepository.impl().find_by_id(id) do
      {:ok, user}
    else
      _ -> {:error, :no_account}
    end
  end

  defp find_user({:email, email}) do
    case UserRepository.impl().find_by_email(email) do
      [user | _] -> {:ok, user}
      [] -> {:error, :no_account}
    end
  end
end

defmodule WebShop.Application.Commands.OAuth.RefreshGrant do
  @moduledoc """
  The app trades its refresh token for a new access token and a new refresh token (rotation).

  A refresh token that was already replaced is presented again: the app moved on, so someone
  else has an old copy. The whole grant is revoked, and the real app has to ask the user again.
  No transaction and no unit of work (see `RevokeGrant`).
  """
  use DDD.Command, transaction: false, unit_of_work: false

  alias WebShop.Application.Commands.OAuth.RevokeGrant
  alias WebShop.Application.OAuth.Tokens
  alias WebShop.Domain.OAuth.Grant
  alias WebShop.Domain.OAuth.Grant.Repository, as: GrantRepository
  alias WebShop.Domain.OAuth.Secret

  command do
    description "Trade a refresh token for a new access token and a new refresh token"

    field :refresh_token, :string,
      required: true,
      sensitive: true,
      description: "The refresh token"

    field :client_id, :string, required: true, description: "The app"
  end

  @impl DDD.Command
  def execute(%__MODULE__{} = command) do
    hash = Secret.hash(command.refresh_token)

    with {:ok, grant} <- find(hash) do
      case Grant.refresh_match(grant, hash) do
        :current -> rotate(grant, command.client_id)
        :previous -> reuse(grant)
        :none -> invalid("unknown refresh token")
      end
    end
  end

  defp find(hash) do
    repo = GrantRepository.impl()

    case repo.find_by_refresh_hash(hash) do
      [grant | _] ->
        {:ok, grant}

      [] ->
        case repo.find_by_previous_refresh_hash(hash) do
          [grant | _] -> {:ok, grant}
          [] -> invalid("unknown refresh token")
        end
    end
  end

  defp rotate(grant, client_id) do
    {refresh_token, refresh_hash} = Secret.generate()
    now = DateTime.truncate(DateTime.utc_now(), :second)

    with :ok <- check_client(grant, client_id),
         {:ok, grant} <- Grant.rotate_refresh(grant, refresh_hash, now),
         {:ok, grant} <- GrantRepository.impl().save(grant) do
      Tokens.issue(grant, refresh_token)
    end
  end

  defp reuse(grant) do
    RevokeGrant.call(%{grant_id: grant.id})
    invalid("the refresh token was already used")
  end

  defp check_client(%Grant{client_id: client_id}, client_id), do: :ok
  defp check_client(_grant, _client_id), do: invalid("the refresh token belongs to another app")

  defp invalid(message) do
    {:error, DDD.Error.business(entity: Grant, code: :invalid_grant, message: message)}
  end
end

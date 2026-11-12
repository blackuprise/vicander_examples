defmodule WebShop.Application.Commands.OAuth.ExchangeCode do
  @moduledoc """
  The app trades the authorization code, with the PKCE verifier it kept, for tokens.

  The code is single use: presenting one that was already traded in means it leaked, and the
  grant is revoked. Two requests with the same code at once resolve to one winner, by the
  grant's version (the second save finds the grant changed and is refused).

  No transaction and no unit of work (see `RevokeGrant`): the revocation of a replayed code has
  to stay although the request fails.
  """
  use DDD.Command, transaction: false, unit_of_work: false

  alias WebShop.Application.Commands.OAuth.RevokeGrant
  alias WebShop.Application.OAuth.Tokens
  alias WebShop.Domain.OAuth.Grant
  alias WebShop.Domain.OAuth.Grant.Repository, as: GrantRepository
  alias WebShop.Domain.OAuth.Secret

  command do
    description "Trade an authorization code for an access token and a refresh token"

    field :code, :string, required: true, sensitive: true, description: "The authorization code"

    field :code_verifier, :string,
      required: true,
      sensitive: true,
      description: "The PKCE verifier"

    field :client_id, :string, required: true, description: "The app"
    field :redirect_uri, :string, required: true, description: "The address the code was sent to"
  end

  @impl DDD.Command
  def execute(%__MODULE__{} = command) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    {refresh_token, refresh_hash} = Secret.generate()

    with {:ok, grant} <- find(command.code),
         :ok <- check_unused(grant),
         {:ok, grant} <-
           Grant.redeem_code(
             grant,
             command.client_id,
             command.redirect_uri,
             command.code_verifier,
             refresh_hash,
             now
           ),
         {:ok, grant} <- GrantRepository.impl().save(grant) do
      Tokens.issue(grant, refresh_token)
    end
  end

  defp find(code) do
    case GrantRepository.impl().find_by_code_hash(Secret.hash(code)) do
      [grant | _] -> {:ok, grant}
      [] -> invalid("unknown code")
    end
  end

  # A code that was traded in is back: whoever has it, the app that got the tokens is no longer
  # the only one, so none of them stay good.
  defp check_unused(grant) do
    if Grant.code_used?(grant) do
      RevokeGrant.call(%{grant_id: grant.id})
      invalid("the code was already used")
    else
      :ok
    end
  end

  defp invalid(message) do
    {:error, DDD.Error.business(entity: Grant, code: :invalid_grant, message: message)}
  end
end

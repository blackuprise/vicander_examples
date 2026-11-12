defmodule WebShop.Application.Commands.OAuth.RevokeGrant do
  @moduledoc """
  Stop a grant from being redeemed or refreshed. Used when a spent code or a replaced refresh
  token shows up again, which means it leaked; access tokens already issued still run out on
  their own, within 15 minutes.

  It writes at once, without a transaction or a unit of work: the commands that call it go on to
  fail (the request is refused), and a failing command writes nothing, which would undo the
  revocation.
  """
  use DDD.Command, transaction: false, unit_of_work: false

  alias WebShop.Domain.OAuth.Grant
  alias WebShop.Domain.OAuth.Grant.Repository, as: GrantRepository

  command do
    description "Revoke a grant"

    field :grant_id, :string, required: true, description: "The grant"
  end

  @impl DDD.Command
  def execute(%__MODULE__{grant_id: grant_id}) do
    with {:ok, grant} <- GrantRepository.impl().find_by_id(grant_id),
         {:ok, grant} <- Grant.revoke(grant, DateTime.truncate(DateTime.utc_now(), :second)) do
      GrantRepository.impl().save(grant)
    end
  end
end

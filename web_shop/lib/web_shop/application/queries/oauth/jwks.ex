defmodule WebShop.Application.Queries.OAuth.Jwks do
  @moduledoc "The public keys the shop's access tokens are verified with (a JWK Set, RFC 7517)."
  use DDD.Query, transaction: false

  alias WebShop.Domain.OAuth.{Settings, TokenSigner}

  query do
    description "The public keys that verify the shop's access tokens"
  end

  @impl DDD.Query
  def execute(%__MODULE__{}) do
    if Settings.mode() == :builtin,
      do: {:ok, TokenSigner.impl().jwks()},
      else: {:error, :not_found}
  end
end

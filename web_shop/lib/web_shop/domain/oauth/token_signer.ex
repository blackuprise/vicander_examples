defmodule WebShop.Domain.OAuth.TokenSigner do
  @moduledoc """
  Port: how the shop signs the access tokens it issues. The adapter holds the key (see
  `WebShop.Infrastructure.OAuth`); the domain only says what goes in a token.
  """

  @doc "Sign `claims` (a map with string keys) into a token."
  @callback sign(claims :: map()) :: {:ok, String.t()} | {:error, term()}

  @doc "The public keys tokens can be verified with, as a JWK Set (RFC 7517)."
  @callback jwks() :: map()

  @doc "How long an access token lives, in seconds."
  @spec lifetime() :: pos_integer()
  def lifetime, do: 15 * 60

  @doc "The adapter configured for this port."
  def impl, do: :web_shop |> Application.fetch_env!(:oauth) |> Keyword.fetch!(:signer)
end

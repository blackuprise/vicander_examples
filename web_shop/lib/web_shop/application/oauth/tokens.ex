defmodule WebShop.Application.OAuth.Tokens do
  @moduledoc """
  What an app is handed when it trades a code or a refresh token: an access token (a signed JWT
  for the MCP endpoint, valid 15 minutes, carrying the user and the scopes but never the role)
  and the refresh token that goes with it. The response shape is RFC 6749's.
  """
  alias WebShop.Domain.OAuth.{Scopes, Settings, TokenSigner}

  @doc "The token response for `grant`, with the (new) `refresh_token` the app is to keep."
  @spec issue(struct(), String.t()) :: {:ok, map()} | {:error, DDD.Error.t()}
  def issue(grant, refresh_token) do
    now = System.os_time(:second)
    lifetime = TokenSigner.lifetime()

    claims = %{
      "iss" => Settings.issuer(),
      "sub" => grant.user_id,
      "aud" => Settings.resource(),
      "scope" => Scopes.format(grant.scopes),
      "client_id" => grant.client_id,
      "iat" => now,
      "exp" => now + lifetime,
      "jti" => DDD.Identity.generate()
    }

    case TokenSigner.impl().sign(claims) do
      {:ok, access_token} ->
        {:ok,
         %{
           access_token: access_token,
           token_type: "Bearer",
           expires_in: lifetime,
           refresh_token: refresh_token,
           scope: Scopes.format(grant.scopes)
         }}

      {:error, reason} ->
        {:error,
         DDD.Error.infrastructure(
           code: :token_signing_failed,
           message: "could not sign the access token: #{inspect(reason)}"
         )}
    end
  end
end

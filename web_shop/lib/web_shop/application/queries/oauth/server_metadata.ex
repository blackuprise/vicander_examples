defmodule WebShop.Application.Queries.OAuth.ServerMetadata do
  @moduledoc """
  The authorization server metadata of the shop (RFC 8414): its endpoints and what it supports.
  Only the shop's own server has any; in external mode the answer is `:not_found`.

  Public clients only (`token_endpoint_auth_methods_supported` is `none`), authorization code
  with PKCE `S256`, refresh tokens, and dynamic registration. The `iss` parameter is returned on
  the redirect (RFC 9207).
  """
  use DDD.Query, transaction: false

  alias WebShop.Domain.OAuth.{Scopes, Settings}

  query do
    description "The OAuth authorization server metadata of the shop"
  end

  @impl DDD.Query
  def execute(%__MODULE__{}) do
    if Settings.mode() == :builtin do
      base = Settings.base_url()

      {:ok,
       %{
         "issuer" => Settings.issuer(),
         "authorization_endpoint" => base <> "/oauth/authorize",
         "token_endpoint" => base <> "/oauth/token",
         "registration_endpoint" => base <> "/oauth/register",
         "jwks_uri" => base <> "/oauth/jwks",
         "response_types_supported" => ["code"],
         "grant_types_supported" => ["authorization_code", "refresh_token"],
         "code_challenge_methods_supported" => ["S256"],
         "token_endpoint_auth_methods_supported" => ["none"],
         "scopes_supported" => Scopes.all(),
         "authorization_response_iss_parameter_supported" => true
       }}
    else
      {:error, :not_found}
    end
  end
end

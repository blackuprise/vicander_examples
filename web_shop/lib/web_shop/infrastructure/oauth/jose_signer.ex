defmodule WebShop.Infrastructure.OAuth.JoseSigner do
  @moduledoc "Signs the shop's access tokens as JWTs (ES256, RFC 9068), with the key of `Keys`."
  @behaviour WebShop.Domain.OAuth.TokenSigner

  alias WebShop.Infrastructure.OAuth.Keys

  @impl WebShop.Domain.OAuth.TokenSigner
  def sign(claims) when is_map(claims) do
    jwk = Keys.signing_key()
    header = %{"alg" => "ES256", "kid" => Keys.kid(jwk), "typ" => "at+jwt"}
    {_modules, token} = jwk |> JOSE.JWT.sign(header, claims) |> JOSE.JWS.compact()
    {:ok, token}
  rescue
    exception -> {:error, exception}
  end

  @impl WebShop.Domain.OAuth.TokenSigner
  def jwks, do: Keys.jwks()
end

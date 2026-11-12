defmodule WebShop.Infrastructure.OAuth.BuiltinVerifier do
  @moduledoc """
  Checks a token the shop issued itself: signed by one of its own keys (ES256, nothing else),
  with the shop as issuer and the MCP endpoint as audience. The subject is the user's id.
  """
  @behaviour WebShop.Domain.OAuth.TokenVerifier

  alias WebShop.Domain.OAuth.Settings
  alias WebShop.Infrastructure.OAuth.{Claims, Keys}

  @impl WebShop.Domain.OAuth.TokenVerifier
  def verify(token) when is_binary(token) do
    with {:ok, claims} <- verified_claims(token),
         :ok <- Claims.check(claims, Settings.issuer(), Settings.audience()),
         sub when is_binary(sub) <- claims["sub"] do
      {:ok,
       %{subject: {:user_id, sub}, scopes: Claims.scopes(claims), client_id: claims["client_id"]}}
    else
      _ -> {:error, :invalid_token}
    end
  end

  def verify(_other), do: {:error, :invalid_token}

  # The first key that vouches for the token. A token that is not a JWT at all makes JOSE raise.
  defp verified_claims(token) do
    Enum.find_value(Keys.keys(), :error, fn jwk ->
      case JOSE.JWT.verify_strict(jwk, ["ES256"], token) do
        {true, %JOSE.JWT{fields: claims}, _jws} -> {:ok, Claims.normalize(claims)}
        _ -> nil
      end
    end)
  rescue
    _ -> :error
  end
end

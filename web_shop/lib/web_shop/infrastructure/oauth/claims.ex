defmodule WebShop.Infrastructure.OAuth.Claims do
  @moduledoc """
  The checks every access token passes, whoever signed it: it was issued by the server we trust,
  for this endpoint, and it has not expired.
  """

  # A little slack for servers whose clocks differ.
  @leeway 30

  @doc "`:ok` if the claims name `issuer` and `audience` and are within their time."
  @spec check(map(), String.t(), String.t(), integer()) :: :ok | :error
  def check(claims, issuer, audience, now \\ System.os_time(:second)) do
    if claims["iss"] == issuer and audience?(claims["aud"], audience) and
         fresh?(claims, now),
       do: :ok,
       else: :error
  end

  @doc """
  The claims of a verified token with JSON `null` as `nil`: JOSE reads it as the atom `:null`,
  which would make a claim that is present but empty look like a value.
  """
  @spec normalize(map()) :: map()
  def normalize(claims) when is_map(claims) do
    Map.new(claims, fn
      {key, :null} -> {key, nil}
      pair -> pair
    end)
  end

  @doc "The scopes in a token: a space separated `scope` (RFC 9068), or a `scp` list."
  @spec scopes(map()) :: [String.t()]
  def scopes(%{"scope" => scope}) when is_binary(scope), do: String.split(scope, " ", trim: true)
  def scopes(%{"scp" => scopes}) when is_list(scopes), do: Enum.filter(scopes, &is_binary/1)
  def scopes(_claims), do: []

  defp audience?(aud, audience) when is_binary(aud), do: aud == audience
  defp audience?(aud, audience) when is_list(aud), do: audience in aud
  defp audience?(_aud, _audience), do: false

  defp fresh?(%{"exp" => exp} = claims, now) when is_integer(exp) do
    exp > now - @leeway and not_before_ok?(claims["nbf"], now)
  end

  defp fresh?(_claims, _now), do: false

  defp not_before_ok?(nil, _now), do: true
  defp not_before_ok?(nbf, now) when is_integer(nbf), do: nbf <= now + @leeway
  defp not_before_ok?(_nbf, _now), do: false
end

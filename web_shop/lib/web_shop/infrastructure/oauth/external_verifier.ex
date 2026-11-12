defmodule WebShop.Infrastructure.OAuth.ExternalVerifier do
  @moduledoc """
  Checks a token another authorization server (Keycloak, Auth0, Entra, ...) issued, for the shop
  running in `:external` mode.

  **The token.** It must be signed with an algorithm from a fixed list (never `none`, never one
  the token picks), by a key the issuer publishes, and name the configured issuer and this
  endpoint as its audience, and not be expired.

  **The keys.** They are read from the issuer's metadata (`jwks_uri`, or what the configuration
  says) and kept for an hour. A token with a key id the cache does not know makes one fetch, and
  no more than one a minute, so a rotation is picked up and a stream of bad tokens does not turn
  into a stream of requests to the issuer. If the issuer can not be reached a key already known
  keeps working. Metadata is only read over `https` (or from `localhost`), and its `issuer` has
  to be the one configured.

  **The user.** The token names a person, not a shop account, so the shop looks the account up by
  the token's `email`, and only when the issuer says it verified it. The role is never taken
  from the token: it is the account's.

  **The scopes.** The shop scopes the token carries, or `shop:read` if it carries none (an
  identity provider that knows nothing of the shop); writing needs `shop:write` explicitly.
  """
  @behaviour WebShop.Domain.OAuth.TokenVerifier

  alias WebShop.Domain.OAuth.{Scopes, Settings}
  alias WebShop.Infrastructure.OAuth.Claims

  @algorithms ["RS256", "ES256", "PS256", "EdDSA"]
  @cache {__MODULE__, :jwks}
  @ttl_ms :timer.hours(1)
  @refetch_gap_ms :timer.minutes(1)
  @loopback ~w(localhost 127.0.0.1 ::1)

  @impl WebShop.Domain.OAuth.TokenVerifier
  def verify(token) when is_binary(token) do
    with {:ok, header} <- header(token),
         true <- header["alg"] in @algorithms,
         {:ok, jwk} <- key(header["kid"]),
         {:ok, claims} <- verified_claims(jwk, header["alg"], token),
         :ok <- Claims.check(claims, Settings.issuer(), Settings.audience()),
         {:ok, email} <- verified_email(claims) do
      {:ok,
       %{
         subject: {:email, email},
         scopes: scopes(claims),
         client_id: claims["azp"] || claims["client_id"]
       }}
    else
      _ -> {:error, :invalid_token}
    end
  end

  def verify(_other), do: {:error, :invalid_token}

  @doc "Forget the cached keys (for tests)."
  @spec reset() :: :ok
  def reset do
    :persistent_term.erase(@cache)
    :ok
  end

  # ── The token ───────────────────────────────────────────────────────────

  # The protected header (`alg`, `kid`) is read before the signature is checked, to pick the key
  # and the algorithm; it is only a lookup key then, and nothing in it is believed until the
  # signature is verified with an algorithm from our own list.
  defp header(token) do
    case token |> JOSE.JWS.peek_protected() |> Jason.decode() do
      {:ok, %{} = map} -> {:ok, map}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp verified_claims(jwk, alg, token) do
    case JOSE.JWT.verify_strict(jwk, [alg], token) do
      {true, %JOSE.JWT{fields: claims}, _jws} -> {:ok, Claims.normalize(claims)}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp verified_email(%{"email" => email} = claims) when is_binary(email) do
    if claims["email_verified"] in [nil, true, "true"] and String.trim(email) != "",
      do: {:ok, email |> String.trim() |> String.downcase()},
      else: :error
  end

  defp verified_email(_claims), do: :error

  defp scopes(claims) do
    case claims |> Claims.scopes() |> Enum.filter(&(&1 in Scopes.all())) do
      [] -> Scopes.default()
      known -> known
    end
  end

  # ── The keys ────────────────────────────────────────────────────────────

  defp key(kid) when is_binary(kid) do
    state = state()

    case {state.keys[kid], fresh?(state)} do
      {nil, _} -> refetch(kid, state)
      {jwk, true} -> {:ok, jwk}
      {_stale, false} -> refetch(kid, state)
    end
  end

  defp key(_kid), do: :error

  defp refetch(kid, state) do
    now = now_ms()

    if may_try?(state, now) do
      case fetch_keys() do
        {:ok, keys} ->
          :persistent_term.put(@cache, %{keys: keys, fetched_at: now, attempted_at: now})
          Map.fetch(keys, kid)

        :error ->
          :persistent_term.put(@cache, %{state | attempted_at: now})
          cached(state, kid)
      end
    else
      cached(state, kid)
    end
  end

  # What the issuer could not be asked for is answered from what is known.
  defp cached(state, kid), do: Map.fetch(state.keys, kid)

  # "Never" is nil, not zero: the monotonic clock starts at a large negative number.
  defp fresh?(%{fetched_at: nil}), do: false
  defp fresh?(%{fetched_at: at}), do: now_ms() - at < @ttl_ms

  defp may_try?(%{attempted_at: nil}, _now), do: true
  defp may_try?(%{attempted_at: at}, now), do: now - at >= @refetch_gap_ms

  defp state do
    :persistent_term.get(@cache, %{keys: %{}, fetched_at: nil, attempted_at: nil})
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp fetch_keys do
    with {:ok, uri} <- jwks_uri(),
         {:ok, %{"keys" => keys}} when is_list(keys) <- get_json(uri) do
      {:ok, for(map <- keys, {kid, jwk} <- [parse_key(map)], into: %{}, do: {kid, jwk})}
    else
      _ -> :error
    end
  end

  defp parse_key(%{"kid" => kid} = map) when is_binary(kid) do
    {kid, JOSE.JWK.from_map(map)}
  rescue
    _ -> nil
  end

  defp parse_key(_map), do: nil

  defp jwks_uri do
    case Keyword.get(Settings.external(), :jwks_uri) do
      nil -> discover()
      uri -> {:ok, uri}
    end
  end

  # OpenID Connect metadata first, then plain OAuth server metadata (RFC 8414).
  defp discover do
    issuer = Settings.issuer()

    Enum.find_value(
      ["/.well-known/openid-configuration", "/.well-known/oauth-authorization-server"],
      :error,
      fn path ->
        case get_json(String.trim_trailing(issuer, "/") <> path) do
          {:ok, %{"issuer" => ^issuer, "jwks_uri" => uri}} when is_binary(uri) -> {:ok, uri}
          _ -> nil
        end
      end
    )
  end

  defp get_json(url) do
    if https_or_loopback?(url) do
      options =
        Keyword.merge(
          [retry: false, receive_timeout: 5_000, redirect: false],
          Settings.req_options()
        )

      case Req.get(url, options) do
        {:ok, %Req.Response{status: 200, body: %{} = body}} -> {:ok, body}
        _ -> :error
      end
    else
      :error
    end
  rescue
    _ -> :error
  end

  defp https_or_loopback?(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) -> true
      %URI{scheme: "http", host: host} -> host in @loopback
      _ -> false
    end
  end
end

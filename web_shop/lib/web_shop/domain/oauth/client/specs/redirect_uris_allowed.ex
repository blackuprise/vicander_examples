defmodule WebShop.Domain.OAuth.Client.Specs.RedirectUrisAllowed do
  @moduledoc """
  The addresses an app may be sent back to after the user agrees: one to five of them, each
  `https`, or `http` on the user's own machine (`localhost`, `127.0.0.1`, `[::1]`) for desktop
  and command line apps. No fragment, no wildcard, no credentials. An authorization code goes to
  one of these, so a loose rule here would let an attacker's app collect another app's codes.
  """
  use DDD.Specification, scope: :value

  @loopback ~w(localhost 127.0.0.1 [::1] ::1)
  @max 5

  @impl DDD.Specification
  def check(uris, _opts) when is_list(uris) do
    cond do
      uris == [] ->
        {:error, :redirect_uris_missing, "needs at least one redirect URI", %{}}

      length(uris) > @max ->
        {:error, :too_many_redirect_uris, "at most #{@max} are allowed", %{}}

      bad = Enum.find(uris, &(not valid?(&1))) ->
        {:error, :redirect_uri_not_allowed,
         "#{inspect(bad)} must be https, or http on localhost, without a fragment or wildcard",
         %{uri: bad}}

      true ->
        :ok
    end
  end

  def check(_other, _opts), do: {:error, :redirect_uris_missing, "must be a list", %{}}

  @doc "Whether one address is an allowed redirect URI."
  @spec valid?(term()) :: boolean()
  def valid?(uri) when is_binary(uri) do
    case URI.parse(uri) do
      %URI{scheme: "https", host: host} = parsed -> plain?(parsed) and host not in [nil, ""]
      %URI{scheme: "http", host: host} = parsed -> plain?(parsed) and host in @loopback
      _ -> false
    end
  end

  def valid?(_other), do: false

  defp plain?(%URI{fragment: nil, userinfo: nil} = parsed),
    do: not String.contains?(URI.to_string(parsed), "*")

  defp plain?(_parsed), do: false
end

defmodule WebShop.Application.OAuth.Access do
  @moduledoc """
  What an access token's scopes allow. A scope only narrows what the user's role allows (the
  role is checked separately, from the account): `shop:read` is for reading, `shop:write` for
  the commands.
  """
  alias WebShop.Domain.OAuth.Scopes

  @doc "The scope a call of the given kind needs."
  @spec required_scope(:read | :write) :: String.t()
  def required_scope(:read), do: Scopes.read()
  def required_scope(:write), do: Scopes.write()

  # The Base64 (URL-safe, no padding) of a SHA-256: 43 characters.
  @challenge ~r/\A[A-Za-z0-9\-_]{43}\z/

  @doc "Whether `value` looks like a PKCE challenge of method S256."
  @spec challenge?(term()) :: boolean()
  def challenge?(value) when is_binary(value), do: Regex.match?(@challenge, value)
  def challenge?(_value), do: false

  @doc "The scopes in an OAuth `scope` parameter: the default when empty, an error when unknown."
  @spec parse_scope(String.t() | nil) :: {:ok, [String.t()]} | {:error, :invalid_scope}
  def parse_scope(text), do: Scopes.parse(text)

  @doc "Every scope there is, with what each lets an app do, for the consent page."
  @spec describe() :: [{String.t(), String.t()}]
  def describe do
    [
      {Scopes.read(), "See products, and your basket and orders (an admin: also the reports)"},
      {Scopes.write(), "Make changes for you (an admin: restock products)"}
    ]
  end
end

defmodule WebShop.Domain.OAuth.Secret do
  @moduledoc """
  The random values an app is handed (an authorization code, a refresh token). Only a hash is
  stored, so a copy of the database does not contain a usable one.
  """

  @doc "A new random value and its hash: `{value, hash}`. The value is 256 random bits."
  @spec generate() :: {String.t(), String.t()}
  def generate do
    value = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    {value, hash(value)}
  end

  @doc "The hash under which a value is stored."
  @spec hash(String.t()) :: String.t()
  def hash(value) when is_binary(value),
    do: :sha256 |> :crypto.hash(value) |> Base.url_encode64(padding: false)
end

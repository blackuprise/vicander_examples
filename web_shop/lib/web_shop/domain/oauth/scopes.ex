defmodule WebShop.Domain.OAuth.Scopes do
  @moduledoc """
  The scopes an app can be given. A scope only *narrows* what the user's own role allows, it
  never widens it: `shop:write` lets an app call the commands, and a customer still can not
  restock.
  """

  @read "shop:read"
  @write "shop:write"

  @doc "Every scope there is."
  @spec all() :: [String.t()]
  def all, do: [@read, @write]

  @doc "What an app gets when it asks for nothing."
  @spec default() :: [String.t()]
  def default, do: [@read]

  @doc "The scope that lets a token call the shop's commands."
  @spec write() :: String.t()
  def write, do: @write

  @doc "The scope that lets a token read."
  @spec read() :: String.t()
  def read, do: @read

  @doc """
  The scopes in an OAuth `scope` parameter (space separated). Nothing asked for is the default;
  a scope that does not exist is an error, not silently dropped.
  """
  @spec parse(String.t() | nil) :: {:ok, [String.t()]} | {:error, :invalid_scope}
  def parse(nil), do: {:ok, default()}

  def parse(text) when is_binary(text) do
    case text |> String.split(" ", trim: true) |> Enum.uniq() do
      [] ->
        {:ok, default()}

      scopes ->
        if Enum.all?(scopes, &(&1 in all())), do: {:ok, scopes}, else: {:error, :invalid_scope}
    end
  end

  @doc "The scopes as an OAuth `scope` parameter."
  @spec format([String.t()]) :: String.t()
  def format(scopes), do: Enum.join(scopes, " ")
end

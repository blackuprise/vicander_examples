defmodule WebShop.Application.OAuth.Endpoints do
  @moduledoc """
  Where the shop's OAuth and MCP endpoints are, for the interface layer, which may not read the
  domain's settings itself.
  """
  alias WebShop.Domain.OAuth.Settings

  @doc "The document that tells a client how to log in to the MCP endpoint (RFC 9728)."
  @spec resource_metadata_url() :: String.t()
  def resource_metadata_url, do: Settings.resource_metadata_url()

  @doc "The issuer, which an authorization response names (RFC 9207)."
  @spec issuer() :: String.t()
  def issuer, do: Settings.issuer()

  @doc "True when the shop is its own authorization server (it serves `/oauth/*`)."
  @spec builtin?() :: boolean()
  def builtin?, do: Settings.mode() == :builtin
end

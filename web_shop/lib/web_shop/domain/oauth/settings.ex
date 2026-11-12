defmodule WebShop.Domain.OAuth.Settings do
  @moduledoc """
  Where the shop is and which authorization server its MCP endpoint trusts. Everything that
  needs the shop's address (the metadata documents, the tokens' issuer and audience) reads it
  here, from `config :web_shop, :oauth`, never from a request: a request's `Host` header is the
  caller's to choose.

    * `:base_url` (`SHOP_BASE_URL`): the shop's public address, `https` in production.
    * `:mode`: `:builtin`, the shop is its own authorization server (the default), or
      `:external`, it only validates tokens another server issued.
    * `:external`: `[issuer: ..., audience: ..., jwks_uri: ...]` for the external mode. The
      audience defaults to the MCP resource URL, `jwks_uri` to what the issuer's metadata says.
    * `:clients`: apps registered by hand, as `%{client_id:, name:, redirect_uris:}`.
  """

  @doc "The OAuth configuration."
  @spec config() :: keyword()
  def config, do: Application.get_env(:web_shop, :oauth, [])

  @doc "The shop's public address, without a trailing slash."
  @spec base_url() :: String.t()
  def base_url do
    config() |> Keyword.get(:base_url, "http://localhost:4000") |> String.trim_trailing("/")
  end

  @doc "`:builtin` or `:external`."
  @spec mode() :: :builtin | :external
  def mode, do: Keyword.get(config(), :mode, :builtin)

  @doc "The address of the MCP endpoint, which is what an access token is issued for."
  @spec resource() :: String.t()
  def resource, do: base_url() <> "/mcp"

  @doc "Where the document describing the MCP endpoint (RFC 9728) is."
  @spec resource_metadata_url() :: String.t()
  def resource_metadata_url, do: base_url() <> "/.well-known/oauth-protected-resource/mcp"

  @doc "The settings of the external server (empty in builtin mode)."
  @spec external() :: keyword()
  def external, do: Keyword.get(config(), :external, [])

  @doc "Who issues the tokens: the shop itself, or the external server."
  @spec issuer() :: String.t()
  def issuer,
    do: if(mode() == :external, do: Keyword.fetch!(external(), :issuer), else: base_url())

  @doc "What a token must be issued for."
  @spec audience() :: String.t()
  def audience do
    if mode() == :external, do: Keyword.get(external(), :audience, resource()), else: resource()
  end

  @doc "Apps registered by hand, with string keys' atoms (`:client_id`, `:name`, `:redirect_uris`)."
  @spec clients() :: [map()]
  def clients, do: Keyword.get(config(), :clients, [])

  @doc "Options for the HTTP client that reads an external server's metadata (tests stub it)."
  @spec req_options() :: keyword()
  def req_options, do: Keyword.get(config(), :req_options, [])
end

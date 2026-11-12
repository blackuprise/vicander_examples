defmodule WebShop.Application.Queries.OAuth.ResourceMetadata do
  @moduledoc """
  The OAuth protected resource metadata of the MCP endpoint (RFC 9728): what a client reads
  after a `401` to learn which authorization server to log in at. It names the shop itself in
  builtin mode and the external server in external mode.
  """
  use DDD.Query, transaction: false

  alias WebShop.Domain.OAuth.{Scopes, Settings}

  query do
    description "The OAuth protected resource metadata of the MCP endpoint"
  end

  @impl DDD.Query
  def execute(%__MODULE__{}) do
    {:ok,
     %{
       "resource" => Settings.resource(),
       "resource_name" => "Web Shop",
       "authorization_servers" => [Settings.issuer()],
       "scopes_supported" => Scopes.all(),
       "bearer_methods_supported" => ["header"]
     }}
  end
end

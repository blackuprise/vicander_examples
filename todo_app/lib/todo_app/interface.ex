defmodule TodoApp.Interface do
  @moduledoc """
  The interface layer: the ways the outside world reaches the application (today the MCP
  server; web endpoints would live here too). It calls the application's commands and queries
  and reads the domain through its ports. Nothing depends on it.
  """
  use Boundary,
    top_level?: true,
    deps: [TodoApp.Domain, TodoApp.Application],
    exports: [MCP, HTTP]
end

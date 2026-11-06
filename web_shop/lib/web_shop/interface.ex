defmodule WebShop.Interface do
  @moduledoc """
  The interface layer: the Phoenix endpoint and LiveViews. It calls the application's commands
  and queries only (never a repository or the domain), so what the web can do is exactly what
  the application offers. Nothing depends on it.
  """
  use Boundary, top_level?: true, deps: [WebShop.Application], exports: [Web.Endpoint]
end

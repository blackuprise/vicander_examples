defmodule WebShop do
  @moduledoc """
  A small web shop built with the `vicander` DDD framework and Phoenix LiveView.

  This module is the composition root: the only place that knows every layer
  (`WebShop.Boot` starts the repo, the framework's supervisor and the web endpoint).
  """
  use Boundary, deps: [WebShop.Application, WebShop.Infrastructure, WebShop.Interface]
end

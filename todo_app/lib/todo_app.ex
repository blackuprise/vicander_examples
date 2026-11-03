defmodule TodoApp do
  @moduledoc """
  A todo application built with the `vicander` DDD framework (`DDD.*`).

  This module is the composition root: the only place that knows every layer
  (`TodoApp.Boot` starts the repo and the framework's supervisor). The layers are
  `TodoApp.Domain`, `TodoApp.Application`, `TodoApp.Infrastructure` and `TodoApp.Interface`.
  """
  use Boundary, deps: [TodoApp.Application, TodoApp.Infrastructure, TodoApp.Interface]
end

defmodule TodoApp.Domain.TodoList.Specs.TitleWithinLimit do
  @moduledoc """
  A text has at most `:max` (default 100) characters. A value spec: attach it with
  `invariant TitleWithinLimit, on: :value, max: 100`.
  """
  use DDD.Specification, scope: :value

  @default_max 100

  @impl DDD.Specification
  def check(value, opts) when is_binary(value) do
    max = Keyword.get(opts, :max, @default_max)
    length = String.length(value)

    if length <= max,
      do: :ok,
      else:
        {:error, :title_too_long, "must be at most #{max} characters",
         %{max: max, length: length}}
  end

  def check(_value, _opts), do: :ok
end

defmodule TodoApp.Domain.User.Specs.ValidEmail do
  @moduledoc """
  The email looks like an address: something, an @, a domain with a dot.

  A value spec: attach it to any string field with `invariant ValidEmail, on: :email`.
  """
  use DDD.Specification, scope: :value

  @impl DDD.Specification
  def check(email, _opts) when is_binary(email) do
    if String.match?(email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/),
      do: :ok,
      else: {:error, :invalid_email, "must be a valid email address", %{email: email}}
  end
end

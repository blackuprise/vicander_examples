defmodule WebShop.Domain.User do
  @moduledoc """
  Aggregate: a person who logs in to the shop, either a `:customer` or an `:admin`.

  Only the password *hash* is kept (the hashing is the application layer's job; the raw password
  is checked by `WebShop.Domain.User.Password` and never stored).
  """
  use DDD.Aggregate

  # The hash stays out of inspect/1, so it stays out of debug logs, crash reports and the console.
  @derive {Inspect, except: [:password_hash]}

  aggregate do
    description "A shop user: a customer who buys, or an admin who manages the catalog"

    identity :id, :uuid
    field :name, :string, required: true, description: "The user's name"
    field :email, :string, required: true, description: "The login email, lowercase"
    field :password_hash, :string, required: true, description: "PBKDF2 hash of the password"
    field :role, {:enum, [:customer, :admin]}, default: :customer, description: "What they may do"

    invariant WebShop.Domain.User.Specs.ValidEmail, on: :email
    invariant WebShop.Domain.User.Specs.NameNotBlank, on: :name
  end

  @doc "True for an administrator."
  @spec admin?(struct()) :: boolean()
  def admin?(%__MODULE__{role: role}), do: role == :admin
end

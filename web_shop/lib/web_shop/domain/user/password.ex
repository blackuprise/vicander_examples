defmodule WebShop.Domain.User.Password do
  @moduledoc "Value object: a plain password that is long enough. Never persisted."
  use DDD.ValueObject

  value_object do
    field :value, :string, required: true

    invariant WebShop.Domain.User.Specs.PasswordLongEnough, on: :value, min: 8
  end
end

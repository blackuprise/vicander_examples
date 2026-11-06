defmodule WebShop.Domain.User.Specs.PasswordLongEnough do
  @moduledoc "A password has at least `:min` characters."
  use DDD.Specification, scope: :value

  @impl DDD.Specification
  def check(password, opts) when is_binary(password) do
    min = Keyword.fetch!(opts, :min)

    if String.length(password) >= min,
      do: :ok,
      else: {:error, :password_too_short, "must have at least #{min} characters", %{min: min}}
  end
end

defmodule WebShop.Application.Queries.User.Authenticate do
  @moduledoc """
  Check an email and password. Answers the same `:invalid_credentials` for an unknown email and
  a wrong password, and spends the hashing time either way, so neither the answer nor the timing
  says which emails are registered.
  """
  use DDD.Query

  alias WebShop.Domain.User.Repository, as: UserRepository

  query do
    description "Check a login: returns the user (without the password hash) or invalid_credentials"

    field :email, :string, required: true, description: "The login email"
    field :password, :string, required: true, description: "The password"
  end

  @impl DDD.Query
  def execute(%__MODULE__{email: email, password: password}) do
    email = email |> String.trim() |> String.downcase()

    case UserRepository.impl().find_by_email(email) do
      [user | _] ->
        if Pbkdf2.verify_pass(password, user.password_hash),
          do: {:ok, WebShop.Application.Queries.User.GetUser.summary(user)},
          else: invalid()

      [] ->
        Pbkdf2.no_user_verify()
        invalid()
    end
  end

  defp invalid, do: {:error, {:invalid_credentials, "Wrong email or password"}}
end

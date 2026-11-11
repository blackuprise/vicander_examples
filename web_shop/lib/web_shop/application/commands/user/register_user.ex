defmodule WebShop.Application.Commands.User.RegisterUser do
  @moduledoc """
  Register a user. The email must be new; the password is validated by the `Password` value
  object and only its PBKDF2 hash is stored.

  `role` defaults to `:customer`. The web registration form never passes it; admins are made
  by `priv/repo/seeds.exs` or `mix shop.create_admin`.
  """
  use DDD.Command

  alias WebShop.Domain.User
  alias WebShop.Domain.User.Password
  alias WebShop.Domain.User.Repository, as: UserRepository

  command do
    description "Register a user with an email and a password (at least 8 characters)"

    field :name, :string, required: true, description: "The user's name"
    field :email, :string, required: true, description: "The login email"

    field :password, :string,
      required: true,
      sensitive: true,
      description: "The password, at least 8 characters"

    field :role, {:enum, [:customer, :admin]}, default: :customer, description: "The user's role"
  end

  @impl DDD.Command
  def execute(%__MODULE__{} = command) do
    email = command.email |> String.trim() |> String.downcase()

    with {:ok, password} <- check_inputs(email, command.password),
         {:ok, user} <-
           User.new(
             name: command.name,
             email: email,
             password_hash: Pbkdf2.hash_pwd_salt(password.value),
             role: command.role
           ) do
      UserRepository.impl().save(user)
    end
  end

  # Both checks run, so the form can show every problem at once.
  defp check_inputs(email, raw_password) do
    password = Password.new(value: raw_password)

    case email_violations(email) ++ password_violations(password) do
      [] -> password
      violations -> {:error, DDD.Error.validation_failed(User, :register, violations)}
    end
  end

  defp email_violations(email) do
    case UserRepository.impl().find_by_email(email) do
      [] -> []
      _ -> [DDD.Error.violation(:email, :email_taken, "is already registered")]
    end
  end

  # The value object reports on `:value`; the caller knows the field as `:password`.
  defp password_violations({:error, %DDD.Error{violations: violations}}),
    do: Enum.map(violations, &%{&1 | field: :password})

  defp password_violations({:ok, _}), do: []
end

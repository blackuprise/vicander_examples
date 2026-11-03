defmodule TodoApp.Application.Commands.User.RegisterUser do
  @moduledoc "Register a user."
  use DDD.Command

  alias TodoApp.Domain.User
  alias TodoApp.Domain.User.Repository, as: UserRepository

  command do
    description "Register a new user"

    field :name, :string, required: true, description: "The user's name"
    field :email, :string, required: true, description: "The user's email address"
  end

  @impl DDD.Command
  def execute(%__MODULE__{name: name, email: email}) do
    with {:ok, user} <- User.new(name: name, email: email) do
      UserRepository.impl().save(user)
    end
  end
end

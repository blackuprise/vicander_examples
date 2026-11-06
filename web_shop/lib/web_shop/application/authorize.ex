defmodule WebShop.Application.Authorize do
  @moduledoc """
  Who may do what. Admin-only commands and queries call `admin/1` with the id of the acting
  user, so the rule is enforced here and not only by hiding buttons in the UI.
  """
  alias WebShop.Domain.User
  alias WebShop.Domain.User.Repository, as: UserRepository

  @doc "`:ok` if the user exists and is an admin, otherwise a `:forbidden` business error."
  @spec admin(binary()) :: :ok | {:error, DDD.Error.t()}
  def admin(user_id) do
    with {:ok, user} <- UserRepository.impl().find_by_id(user_id),
         true <- User.admin?(user) do
      :ok
    else
      _ ->
        {:error,
         DDD.Error.business(
           entity: User,
           entity_id: user_id,
           code: :forbidden,
           message: "only an admin can do this"
         )}
    end
  end
end

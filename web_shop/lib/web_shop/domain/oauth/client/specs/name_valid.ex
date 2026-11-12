defmodule WebShop.Domain.OAuth.Client.Specs.NameValid do
  @moduledoc "An app's name: something to show on the consent page, not a novel."
  use DDD.Specification, scope: :value

  @max 100

  @impl DDD.Specification
  def check(name, _opts) when is_binary(name) do
    trimmed = String.trim(name)

    cond do
      trimmed == "" ->
        {:error, :name_blank, "can't be blank", %{}}

      String.length(trimmed) > @max ->
        {:error, :name_too_long, "at most #{@max} characters", %{}}

      String.match?(trimmed, ~r/[\x00-\x1f\x7f]/) ->
        {:error, :name_invalid, "has control characters", %{}}

      true ->
        :ok
    end
  end
end

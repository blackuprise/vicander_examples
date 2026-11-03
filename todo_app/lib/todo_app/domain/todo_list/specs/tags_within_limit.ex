defmodule TodoApp.Domain.TodoList.Specs.TagsWithinLimit do
  @moduledoc """
  An item has at most `:max` (default 5) tags, each one not blank and at most `:max_length`
  (default 20) characters, and no tag twice. A value spec: `on: :tags`.
  """
  use DDD.Specification, scope: :value

  @default_max 5
  @default_max_length 20

  @impl DDD.Specification
  def check(tags, opts) do
    max = Keyword.get(opts, :max, @default_max)
    max_length = Keyword.get(opts, :max_length, @default_max_length)

    cond do
      length(tags) > max ->
        {:error, :too_many_tags, "at most #{max} tags", %{max: max, count: length(tags)}}

      Enum.any?(tags, &(String.trim(&1) == "")) ->
        {:error, :blank_tag, "a tag must not be blank"}

      long = Enum.find(tags, &(String.length(&1) > max_length)) ->
        {:error, :tag_too_long, "a tag is at most #{max_length} characters",
         %{max_length: max_length, tag: long}}

      tags != Enum.uniq(tags) ->
        {:error, :duplicate_tag, "a tag is used twice", %{tags: tags -- Enum.uniq(tags)}}

      true ->
        :ok
    end
  end
end

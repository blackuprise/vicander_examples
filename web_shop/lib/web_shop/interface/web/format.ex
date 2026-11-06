defmodule WebShop.Interface.Web.Format do
  @moduledoc "Small helpers to show and read money, dates and errors."

  @doc "Cents as dollars: `1250` becomes `\"$12.50\"`."
  def money(cents) when is_integer(cents) do
    sign = if cents < 0, do: "-", else: ""
    abs = abs(cents)

    "#{sign}$#{div(abs, 100)}.#{abs |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  @doc """
  Reads a price like `12`, `12.5` or `12.50` into cents. Anything else is an error. (Not parsed
  with `Decimal`: a text like `1e999999999` must not become a huge number.)
  """
  def parse_cents(text) when is_binary(text) do
    case Regex.run(~r/^(\d{1,7})(?:\.(\d{1,2}))?$/, String.trim(text)) do
      [_, whole] ->
        {:ok, String.to_integer(whole) * 100}

      [_, whole, fraction] ->
        {:ok,
         String.to_integer(whole) * 100 + String.to_integer(String.pad_trailing(fraction, 2, "0"))}

      _ ->
        :error
    end
  end

  @doc "A whole number of up to 6 digits, or `:error`."
  def parse_int(text) when is_binary(text) do
    if Regex.match?(~r/^\d{1,6}$/, String.trim(text)),
      do: {:ok, text |> String.trim() |> String.to_integer()},
      else: :error
  end

  @doc "A date or datetime as `2026-11-06 14:03`."
  def datetime(%DateTime{} = value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M")

  @doc "The sentence to show for a failed command or query."
  def error(%DDD.Error{violations: [%{message: message} | _]}), do: message
  def error(%DDD.Error{message: message}), do: message
  def error(_other), do: "Something went wrong. Please try again."

  @doc "Messages by form field, from a `DDD.Error`."
  def field_errors(%DDD.Error{} = error), do: DDD.Error.to_map(error)
  def field_errors(_), do: %{}
end

defmodule WebShop.Infrastructure.LogRedactor do
  @moduledoc """
  A logger filter that hides secrets. The framework logs every command's and query's parameters
  at debug level, so without this a `RegisterUser` or `Authenticate` line would print the
  password. `password: "..."` and `password_hash: "..."` become `"[FILTERED]"` in every message.
  """

  @secret ~r/(password(?:_hash)?:\s*)"(?:[^"\\]|\\.)*"/

  @doc "Installs the filter on the logger (once; calling it again is harmless)."
  @spec install() :: :ok
  def install do
    _ = :logger.add_primary_filter(:redact_secrets, {&__MODULE__.filter/2, []})
    :ok
  end

  @doc false
  def filter(%{msg: {:string, message}} = event, _extra) do
    %{event | msg: {:string, message |> IO.chardata_to_string() |> redact()}}
  end

  def filter(event, _extra), do: event

  @doc "The text with the values of password fields replaced."
  @spec redact(String.t()) :: String.t()
  def redact(text), do: Regex.replace(@secret, text, ~S(\1"[FILTERED]"))
end

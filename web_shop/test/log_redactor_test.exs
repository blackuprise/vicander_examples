defmodule WebShop.LogRedactorTest do
  use WebShop.DataCase

  import ExUnit.CaptureLog

  alias WebShop.Application.Commands.User.RegisterUser
  alias WebShop.Infrastructure.LogRedactor

  test "redact/1 hides password values and nothing else" do
    text =
      ~S(%{name: "Ann", password: "s3cret \"x\"", password_hash: "$pbkdf2$abc", role: :admin})

    redacted = LogRedactor.redact(text)

    assert redacted =~ ~S(password: "[FILTERED]")
    assert redacted =~ ~S(password_hash: "[FILTERED]")
    assert redacted =~ ~S(name: "Ann")
    refute redacted =~ "s3cret"
    refute redacted =~ "pbkdf2"
  end

  test "a command logged at debug level never shows the password" do
    LogRedactor.install()
    LogRedactor.install()
    previous = Logger.level()
    Logger.configure(level: :debug)

    on_exit(fn ->
      Logger.configure(level: previous)
      :logger.remove_primary_filter(:redact_secrets)
    end)

    log =
      capture_log([level: :debug], fn ->
        RegisterUser.call!(%{
          name: "Ann",
          email: "ann@example.com",
          password: "very-secret-password"
        })
      end)

    assert log =~ "RegisterUser"
    refute log =~ "very-secret-password"
  end
end

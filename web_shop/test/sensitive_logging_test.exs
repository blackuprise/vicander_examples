defmodule WebShop.SensitiveLoggingTest do
  # The framework logs every command and query at debug level. The password fields are
  # `sensitive: true`, so what is logged never has them; nothing filters the text afterwards.
  use WebShop.DataCase

  import ExUnit.CaptureLog

  alias WebShop.Application.Commands.User.RegisterUser
  alias WebShop.Application.Queries.User.Authenticate

  @password "very-secret-password"

  test "registering is logged without the password, and with the rest" do
    log =
      capture_log([level: :debug], fn ->
        RegisterUser.call!(%{name: "Ann", email: "ann@example.com", password: @password})
      end)

    assert log =~ "RegisterUser started"
    assert log =~ "ann@example.com"
    refute log =~ @password
  end

  test "logging in is logged without the password, also when it is wrong" do
    register!()

    for password <- ["long-enough-password", "a-wrong-password"] do
      log =
        capture_log([level: :debug], fn ->
          Authenticate.call(%{email: "ann@example.com", password: password})
        end)

      assert log =~ "Authenticate started"
      assert log =~ "ann@example.com"
      refute log =~ password
    end
  end

  test "the password hash is in neither the user's inspect nor the debug log" do
    log =
      capture_log([level: :debug], fn ->
        register!()
        Authenticate.call(%{email: "ann@example.com", password: "long-enough-password"})
      end)

    %{rows: [[hash]]} =
      WebShop.Infrastructure.Repo.query!("SELECT password_hash FROM users WHERE email = $1", [
        "ann@example.com"
      ])

    assert String.starts_with?(hash, "$pbkdf2")
    refute log =~ hash

    {:ok, user} =
      WebShop.Domain.User.new(name: "Ann", email: "ann@example.com", password_hash: hash)

    refute inspect(user) =~ hash
  end

  test "the password is still in the command, only hidden from inspect" do
    {:ok, command} =
      RegisterUser.new(%{name: "Ann", email: "ann@example.com", password: @password})

    assert command.password == @password
    refute inspect(command) =~ @password
  end
end

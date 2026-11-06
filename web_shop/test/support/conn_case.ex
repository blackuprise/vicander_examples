defmodule WebShop.ConnCase do
  @moduledoc "Test case for LiveView tests: the database sandbox plus a logged-in connection helper."
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import Plug.Conn
      import WebShop.ConnCase

      import WebShop.DataCase,
        only: [
          register!: 0,
          register!: 1,
          register!: 2,
          admin!: 0,
          product!: 1,
          product!: 2,
          add_to_basket!: 2,
          add_to_basket!: 3
        ]

      @endpoint WebShop.Interface.Web.Endpoint
    end
  end

  setup tags do
    pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(WebShop.Infrastructure.Repo,
        shared: not tags[:async]
      )

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    %{conn: Phoenix.ConnTest.build_conn()}
  end

  @doc "A connection with `user` logged in."
  def log_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end
end

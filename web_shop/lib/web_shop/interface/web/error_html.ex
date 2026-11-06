defmodule WebShop.Interface.Web.ErrorHTML do
  @moduledoc "Plain-text error pages."
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end

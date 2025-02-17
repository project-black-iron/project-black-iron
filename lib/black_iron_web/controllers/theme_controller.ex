defmodule BlackIronWeb.ThemeController do
  @moduledoc """
  Controller for the /theme endpoint
  Changes user theme via cookie
  """
  use BlackIronWeb, :controller

  def update(conn, params) do
    redirect_to = case params["redirect_to"] do
      path = "/" <> _ -> path
      _ -> "/"
    end
    # TODO: set theme in cookie
    redirect(conn, to: redirect_to)
  end
end

defmodule TaskyWeb.PageController do
  use TaskyWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

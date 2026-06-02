defmodule TaskyWeb.PageController do
  use TaskyWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def handbook(conn, _params) do
    render(conn, :handbook)
  end
end

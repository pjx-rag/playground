defmodule PlaygroundWeb.PageController do
  use PlaygroundWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

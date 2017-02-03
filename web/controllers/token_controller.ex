defmodule Shield.TokenController do
  use Shield.Web, :controller
  use Shield.HookImporter
  alias Authable.OAuth2, as: OAuth2

  @repo Application.get_env(:authable, :repo)
  @user Application.get_env(:authable, :resource_owner)
  @client Application.get_env(:authable, :client)
  @token_store Application.get_env(:authable, :token_store)
  @renderer Application.get_env(:authable, :renderer)
  @views Application.get_env(:shield, :views)
  @hooks Application.get_env(:shield, :hooks)

  plug :before_token_create when action in [:create]

  # GET /tokens/:id
  def show(conn, %{"id" => token_value, "client_id" => client_id, "client_secret" => secret}) do
    token = @repo.get_by(@token_store, value: token_value)
    if is_nil(token) do
      conn
      |> put_status(:not_found)
      |> render(@views[:error], "404.json")
      |> halt
    else
      client = @repo.get_by(@client, id: client_id, secret: secret)
      if is_nil(client) ||
        Map.get(token.details, "client_id", "") != client_id do
        conn
        |> put_status(:not_found)
        |> render(@views[:error], "404.json")
      else
        conn
        |> put_status(:ok)
        |> render(@views[:token], "show.json", token: token)
      end
    end
  end
  def show(conn, _) do
    @renderer.render(conn, :unprocessable_entity, %{errors:
      %{details: "missing client_id and/or client_secret!"}})
  end

  # POST /tokens
  def create(conn, %{"token" => params}),
    do: create(conn, params)
  def create(conn, params) do
    case OAuth2.authorize(params) do
      {:error, errors, http_status_code} ->
        conn
        |> @hooks.after_token_create_failure(errors, http_status_code)
        |> @renderer.render(http_status_code, %{errors: errors})
      token ->
        conn
        |> @hooks.after_token_create_success(token)
        |> put_status(:created)
        |> render(@views[:token], "show.json", token: token)
    end
  end
end

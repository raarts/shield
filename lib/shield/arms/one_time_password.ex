defmodule Shield.Arm.OneTimePassword do
  @moduledoc """
  A behaviour for all Shield.Arm module for one time password security challange.
  """

  import Ecto.Query
  import Plug.Conn
  alias Ecto.Multi

  @behaviour Shield.Arm
  @renderer Application.get_env(:authable, :renderer)
  @repo Application.get_env(:authable, :repo)
  @resource_owner Application.get_env(:authable, :resource_owner)
  @token_store Application.get_env(:authable, :token_store)
  @ten_years_in_seconds 315360000
  @token_name "otp_secret_token"

  def init(opts) do
    {
      Keyword.get(opts, :enabled, false),
      Keyword.get(opts, :params_namespace, "")
    }
  end

  def call(conn, {false, _}),
    do: conn
  def call(conn, {enabled, params_namespace}),
    do: defend(conn, {enabled, params_namespace})

  def defend(conn, {true, params_namespace}) do
    otp_value =
      case params_namespace do
        "" ->
          conn.params
          |> Map.get("otp_value", "")
        _ ->
          conn.params
          |> Map.get(params_namespace, %{})
          |> Map.get("otp_value", "")
      end

    defend_conn(conn, {conn.assigns[:current_user], otp_value})
  end

  def generate_otp_secret do
    otp_secret_token = Comeonin.Otp.gen_secret
    encrypted_otp_secret_token = encrypt_val(otp_secret_token)

    query = from t in @token_store,
              where: t.value == ^encrypted_otp_secret_token and
              t.name == "otp_secret_token",
              limit: 1

    case List.first(@repo.all(query)) do
      nil -> otp_secret_token
      token -> generate_otp_secret
    end
  end

  def disable(user, otp_value) do
    settings = Map.put(user.settings || %{}, "otp_enabled", false)
    settings_changeset = @resource_owner.settings_changeset(user, settings)

    case find_otp_secret_token(user) do
      nil ->
        {:error, %{otp_secret_token: ["Not found"]}}
      token ->
        case is_valid?(token.value, otp_value) do
          true ->
            queries =
              Multi.new
              |> Multi.delete(:otp_secret_token, token)
              |> Multi.update(:user, settings_changeset)

            {:ok, _} = @repo.transaction(queries)
          false ->
            {:error, %{otp_value: ["Invalid one time password"]}}
        end
    end
  end

  def enable(user, otp_secret, otp_value) do
    case Map.get(user.settings, "otp_enabled", false) do
      true ->
        {:error, %{opt_enabled: ["Already enabled"]}}
      false ->
        encrypted_otp_secret = encrypt_val(otp_secret)
        case is_valid?(encrypted_otp_secret, otp_value) do
          true ->
            enable_otp_for_user_with_token(user, encrypted_otp_secret)
          false ->
            {:error, %{otp_value: ["Invalid one time password"]}}
        end
    end
  end

  defp enable_otp_for_user_with_token(user, otp_secret) do
    token_changeset = @token_store.changeset(%@token_store{}, %{
      user_id: user.id,
      name: @token_name,
      expires_at: :os.system_time(:seconds) + @ten_years_in_seconds
    })

    changes =
      token_changeset
      |> Map.get(:changes)
      |> Map.put(:value, otp_secret)

    token_changeset =
      token_changeset
      |> Map.put(:changes, changes)

    settings = Map.put(user.settings || %{}, "otp_enabled", true)
    settings_changeset = @resource_owner.settings_changeset(user,
      %{settings: settings})

    queries =
      Multi.new
      |> Multi.insert(:otp_secret_token, token_changeset)
      |> Multi.update(:user, settings_changeset)

    {:ok, _} = @repo.transaction(queries)
  end

  defp is_valid?(encrypted_otp_secret_token, otp_value) do
    otp_secret = decrypt_val(encrypted_otp_secret_token)
    case Comeonin.Otp.check_totp(otp_value, otp_secret) do
      false -> false
      result -> is_integer(result) && (
          result
          |> Integer.to_string
          |> String.match?(~r/(^[\d]+$)/)
        )
    end
  end

  defp find_otp_secret_token(user) do
    query = from t in @token_store,
      where: t.user_id == ^user.id and t.name == ^@token_name, limit: 1

    query
    |> @repo.all
    |> List.first
  end

  defp defend_conn(conn, {nil, _}),
    do: conn
  defp defend_conn(conn, {current_user, otp_value}) do
    case Map.get(current_user.settings || %{}, "otp_enabled", false) do
      true ->
        case is_valid?(find_otp_secret_token(current_user).value, otp_value) do
          true ->
            conn
          false ->
            conn
            |> @renderer.render(:forbidden, %{errors: %{otp_value:
                 "Invalid one time password."}})
            |> halt
        end
      _ ->
        conn
        |> @renderer.render(:forbidden, %{errors: %{otp_required:
             "One time password required to access resource."}})
        |> halt
    end
  end

  defp encrypt_val(val),
    do: val

  defp decrypt_val(val),
    do: val
end

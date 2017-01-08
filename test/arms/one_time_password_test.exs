defmodule Shield.Arm.OneTimePasswordTest do
  use Shield.ConnCase
  import Shield.Factory
  alias Shield.Arm.OneTimePassword, as: OneTimePasswordPlug
  alias Comeonin.Otp

  @repo Application.get_env(:authable, :repo)
  @user Application.get_env(:authable, :resource_owner)
  @opts OneTimePasswordPlug.init([enabled: true, params_namespace: "user"])

  setup do
    {:ok, conn: build_conn()}
  end

  test "defend with valid otp code", %{conn: conn} do
    user = insert(:user, settings: %{})
    otp_secret = Otp.gen_secret
    otp_value = Otp.gen_totp(otp_secret)
    {:ok, _} = OneTimePasswordPlug.enable(user, otp_secret, otp_value)
    user = @repo.get(@user, user.id)

    conn =
      conn
      |> Map.put(:params, %{"user" => %{"otp_value" => otp_value} })
      |> assign(:current_user, user)
      |> OneTimePasswordPlug.call(@opts)

    assert conn.state == :unset
    assert conn.status != 403
  end

  test "defend with invalid otp code", %{conn: conn} do
    user = insert(:user, settings: %{})
    otp_secret = Otp.gen_secret
    otp_value = Otp.gen_totp(otp_secret)
    {:ok, _} = OneTimePasswordPlug.enable(user, otp_secret, otp_value)
    conn = conn |> assign(:current_user, user) |> OneTimePasswordPlug.call({true, "123456"})
    assert conn.state == :set
    assert conn.status == 403
  end

  test "defend with invalid otp code, when defend not enabled!", %{conn: conn} do
    user = insert(:user, settings: %{"otp_enabled" => false})
    conn = conn |> assign(:current_user, user) |> OneTimePasswordPlug.call({false, ""})
    assert conn.state == :unset
    assert conn.status != 403
  end

  test "disable otp code with valid code and currently enabled" do
    user = insert(:user, settings: %{})
    otp_secret = Otp.gen_secret
    otp_value = Otp.gen_totp(otp_secret)
    {:ok, _} = OneTimePasswordPlug.enable(user, otp_secret, otp_value)
    assert {:ok, _} = OneTimePasswordPlug.disable(user, otp_value)
  end

  test "disable otp code with valid code and currently not enabled" do
    user = insert(:user, settings: %{"otp_enabled" => false})
    otp_secret = Otp.gen_secret
    otp_value = Otp.gen_totp(otp_secret)
    result = OneTimePasswordPlug.disable(user, otp_value)
    assert {:error, %{otp_secret_token: ["Not found"]}} == result
  end

  test "disable otp code with invalid code and currently enabled" do
    user = insert(:user, settings: %{"otp_enabled" => false})
    otp_secret = Otp.gen_secret
    otp_value = Otp.gen_totp(otp_secret)
    {:ok, _} = OneTimePasswordPlug.enable(user, otp_secret, otp_value)
    result = OneTimePasswordPlug.disable(user, "123456")
    assert {:error, %{otp_value: ["Invalid one time password"]}} == result
  end

  test "enable otp code with valid code and currently not enabled" do
    user = insert(:user, settings: %{})
    otp_secret = Otp.gen_secret
    otp_value = Otp.gen_totp(otp_secret)
    assert {:ok, _} = OneTimePasswordPlug.enable(user, otp_secret, otp_value)
  end

  test "enable otp code with valid code and currently enabled" do
    user = insert(:user, settings: %{"otp_enabled" => true})
    otp_secret = Otp.gen_secret
    otp_value = Otp.gen_totp(otp_secret)
    result = OneTimePasswordPlug.enable(user, otp_secret, otp_value)
    assert {:error, %{opt_enabled: ["Already enabled"]}} == result
  end

  test "enable otp code with invalid code and currently not enabled" do
    user = insert(:user, settings: %{})
    otp_secret = Otp.gen_secret
    otp_value = "123456"
    result = OneTimePasswordPlug.enable(user, otp_secret, otp_value)
    assert {:error, %{otp_value: ["Invalid one time password"]}} == result
  end
end

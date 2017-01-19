# Shield

Shield is an OAuth2 Provider hex package and also a standalone microservice build top of the Phoenix Framework and 'authable' package.

Shield can be used inside an application or can be used as standalone microservice. Shield simply plays role of the 'authorization server' on OAuth2 scheme.

## Installation

### As Package

The package can be installed as:

  1. Add shield to your list of dependencies in `mix.exs` and run `mix deps.get
`:

    ```elixir
    def deps do
      [{:shield, "~> 0.4.0"}]
    end
    ```

  2. Ensure shield is started before your application:

    ```elixir
    def application do
      [applications: [:shield]]
    end
    ```

  3. Add authable configurations to your `config/config.exs` file:

    ```elixir
    config :authable,
      ecto_repos: [Authable.Repo],
      repo: Authable.Repo,
      resource_owner: Authable.Model.User,
      token_store: Authable.Model.Token,
      client: Authable.Model.Client,
      app: Authable.Model.App,
      expires_in: %{
        access_token: 3600,
        refresh_token: 24 * 3600,
        authorization_code: 300,
        session_token: 30 * 24 * 3600
      },
      grant_types: %{
        authorization_code: Authable.GrantType.AuthorizationCode,
        client_credentials: Authable.GrantType.ClientCredentials,
        password: Authable.GrantType.Password,
        refresh_token: Authable.GrantType.RefreshToken
      },
      auth_strategies: %{
        headers: %{
          "authorization" => [
            {~r/Basic ([a-zA-Z\-_\+=]+)/, Authable.Authentication.Basic},
            {~r/Bearer ([a-zA-Z\-_\+=]+)/, Authable.Authentication.Bearer},
          ],
          "x-api-token" => [
            {~r/([a-zA-Z\-_\+=]+)/, Authable.Authentication.Bearer}
          ]
        },
        query_params: %{
          "access_token" => Authable.Authentication.Bearer
        },
        sessions: %{
          "session_token" => Authable.Authentication.Session
        }
      },
      scopes: ~w(read write session),
      renderer: Authable.Renderer.RestApi
    ```

  4. Add shield notifier configurations to your `config/config.exs` file:

    ```elixir
    config :shield_notifier,
      channels: %{
        email: %{
          from: {
            System.get_env("APP_NAME") || "Shield Notifier",
            System.get_env("APP_FROM_EMAIL") || "no-reply@localhost"}
        }
      }
    ```

  5. Add your favorite mail sender Bamboo adapter configuration to your `config/prod.exs` file:

    ```elixir
    config :shield_notifier, Shield.Notifier.Mailer,
      adapter: Bamboo.SendgridAdapter,
      api_key: System.get_env("SENDGRID_API_KEY")
    ```

  6. Add shield configurations to your `config/config.exs` file:

    ```elixir
    config :shield,
      confirmable: true,
      hooks: Shield.Hook.Default,
      views: %{
        changeset: Shield.ChangesetView,
        error: Shield.ErrorView,
        app: Shield.AppView,
        client: Shield.ClientView,
        token: Shield.TokenView,
        user: Shield.UserView
      },
      cors_origins: "http://localhost:4200, *",
      front_end: %{
        base: "http://localhost:4200",
        confirmation_path: "/users/confirm?confirmation_token={{confirmation_token}}",
        reset_password_path: "/users/reset-password?reset_token={{reset_token}}"
      }
    ```

  If you want to disable a authorization strategy, then delete it from shield configuration.

  If you want to add a new authorization strategy then add your own module.

  5. Use installer to generate controllers, views, models and migrations from originals

    ```elixir
    # Run only if you need to change behaviours, otherwise skip this.
    mix shield.install
    ```

  6. Add database configurations for the `Authable.Repo` on env config files:

    ```elixir
    config :authable, Authable.Repo,
      adapter: Ecto.Adapters.Postgres,
      username: "postgres",
      password: "",
      database: "",
      hostname: "",
      pool_size: 10
    ```
  7. Run migrations for Authable.Repo (Note: all id fields are UUID type):

    ```elixir
    mix ecto.create
    mix ecto.migrate -r Authable.Repo
    ```

  8. Add routes

    ```elixir
    pipeline :api do
      plug :accepts, ["json"]
    end

    scope "/", Shield do
      pipe_through :api
      resources "/clients", ClientController, except: [:new, :edit]

      get     "/apps", AppController, :index
      get     "/apps/:id", AppController, :show
      delete  "/apps/:id", AppController, :delete
      post    "/apps/authorize", AppController, :authorize

      get     "/tokens/:id", TokenController, :show
      post    "/tokens", TokenController, :create

      post    "/users/register", UserController, :register
      post    "/users/login", UserController, :login
      delete  "/users/logout", UserController, :logout
      get     "/users/me", UserController, :me
      get     "/users/confirm", UserController, :confirm
      post    "/users/recover_password", UserController, :recover_password
      post    "/users/reset_password", UserController, :reset_password
      post    "/users/change_password", UserController, :change_password
    end
    ```

  9. You are ready to go!

### Standalone

    git clone git@github.com:mustafaturan/shield.git
    cd shield
    mix deps.get
    mix ecto.create -r Authable.Repo
    mix ecto.migrate -r Authable.Repo
    mix phoenix.server

### API Endpoints Documentation

You can use paste the content of swagger.yml to [http://editor.swagger.io/](http://editor.swagger.io/) [https://raw.githubusercontent.com/mustafaturan/shield/master/swagger.yml](https://raw.githubusercontent.com/mustafaturan/shield/master/swagger.yml).

### Heroku

[![Deploy](https://www.herokucdn.com/deploy/button.png)](https://heroku.com/deploy)

## Usage, Examples & Configuration

### Protecting resources

Inside your controller modules; add the following lines to restrict access to actions.

```elixir
# Add plug to restrict access to all actions
plug Authable.Plug.Authenticate, [scopes: ~w(read)]

# Example inside module

defmodule SomeModule.AppController do
  use SomeModule.Web, :controller
  ...
  plug Authable.Plug.Authenticate, [scopes: ~w(read write)]

  def index(conn, _params) do
    # access to current user on successful authentication
    current_user = conn.assigns[:current_user]
    ...
  end

  ...
end
```

If you need to restrict specific resource, you may guard with when clause. Forexample, to check authentication only on :create, :update and :delete actions of your controllers.

```elixir
plug Authable.Plug.Authenticate, [scopes: ~w(read write)] when action in [:create, :update, :delete]
```

Incase you do not want to allow registered user to access resources:

```elixir
# Add plug `Authable.Plug.UnauthorizedOnly` for necessary actions
plug :Authable.Plug.UnauthorizedOnly when action in [:register]

# Example inside module

defmodule SomeModule.AppController do
  use SomeModule.Web, :controller
  ...

  plug Authable.Plug.Authenticate, [scopes: ~w(read write)] when action in [:create]
  plug Authable.Plug.UnauthorizedOnly when action in [:register]

  def register(conn, _params) do
    # if user logged in, then will response automatically with
    # unprocessable_entity 422 header and error
    ...
  end

  def create(conn, params) do
    # access to current user on successful authentication
    current_user = conn.assigns[:current_user]
    ...
  end

  ...
end
```

Manually handling authentication:

```elixir
defmodule SomeModule.AppController do
  use SomeModule.Web, :controller
  ...
  import Authable.Helper

  def register(conn, _params) do
    required_scopes = ~w(session)
    case authorize_for_resource(conn, required_scopes) do
      {:ok, current_user} -> IO.puts(current_user.email)
      {:error, errors, _} -> IO.inspect(errors)
      nil -> IO.puts("not authencated!")
    end
    ...
  end
end
```

### Accessing resource owner info

By default `Authable.Model.User` represents resource owner. To access resource owner, plug `Authable.Plug.Authenticate` must be called. Then current user information will be available by conn assignments.

```elixir
conn.assigns[:current_user]
```

### Allowing only email confirmed user to access resources

To allow only confirmed user to access certain resources, you need to add confirmable plug to your controllers

```elixir
  plug Shield.Arm.Confirmable, [enabled: Application.get_env(:shield, :confirmable)] when action in [:me, :change_password]
```

### Views

By default REST style views are used to represent error and data models. In shield configuration, it is possible to change view modules to represent non-rest style data models like JSON-API or any other data model.

## Hooks

In shield package; by default hooks do nothing, but when you need to implement a callback after or before execution of functions, it might be very useful. All you need to do is create a module that use the hook behaviour module and then update the config.exs.

Sample module implementation:

```elixir
defmodule Shield.Hook.Sample do
  use Shield.Hook
  ...

  def before_app_authorize(conn, params) do
    # do sth...
    conn
  end
  ...
end
```

Here is supported hooks and return types:

```elixir
def before_app_authorize(conn, _), do: conn
def after_app_authorize_failure(conn, errors, status), do: conn
def after_app_authorize_success(conn, token), do: conn
def before_app_delete(conn, _), do: conn
def after_app_delete(conn), do: conn
def before_client_create(conn, _), do: conn
def after_client_create_success(conn, client), do: conn
def after_client_create_failure(conn, changeset), do: conn
def before_client_update(conn, _), do: conn
def after_client_update_failure(conn, changeset), do: conn
def after_client_update_success(conn, client), do: conn
def before_client_delete(conn, _), do: conn
def after_client_delete(conn), do: conn
def before_token_create(conn, _), do: conn
def after_token_create_failure(conn, errors, status), do: conn
def after_token_create_success(conn, token), do: conn
def before_user_register(conn, _), do: conn
def after_user_register_failure(conn, changeset), do: conn
def after_user_register_success(conn, user), do: conn
def before_user_login(conn, _), do: conn
def after_user_login_failure(conn, errors, http_status_code), do: conn
def after_user_login_token_failure(conn, changeset), do: conn
def after_user_login_token_success(conn, token), do: conn
```

## Client Implementations

Since 'shield' application is a microservice. Several client applications might be written using shield. Please do not hesitate to raise an issue with your implementation, description and demo url.

### Notes

API may change up to v1.0

## Contributing

### Issues, Bugs, Documentation, Enhancements

  1. Fork the project

  2. Make your improvements and write your tests.

  3. Document what you did/change.

  4. Make a pull request.

### To add new strategy

Shield and Authable are extensible modules, you can create your strategy and share as hex package(Which can be listed on Wiki pages).

## Todo

  - [x] [Swagger documentation](../master/swagger.yml)

  - [x] Sample UI Client: https://github.com/mustafaturan/shield/tree/ui

  - [x] Sample resource server implementation https://github.com/mustafaturan/shield-blog-sample

  - [ ] Background job to delete expired tokens

  - [ ] Optional one time password protection

  - [ ] Optional captcha protection

## References

https://tools.ietf.org/html/rfc6749

https://github.com/mustafaturan/authable

https://hexdocs.pm/authable

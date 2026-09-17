defmodule FluentlyWeb.Router do
  use FluentlyWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FluentlyWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :demo do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/demo", FluentlyWeb do
    pipe_through :demo
    get "/comments", DemoController, :index
    post "/comments", DemoController, :create
    post "/comments/:thread_id/replies", DemoController, :reply
    patch "/comments/:thread_id", DemoController, :update
  end

  scope "/", FluentlyWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/signup", AccountController, :signup
    post "/signup", AccountController, :register
    get "/login", AccountController, :login
    post "/login", AccountController, :authenticate
    get "/app/login", ManageController, :login
    post "/app/login", ManageController, :authenticate
    post "/app/logout", ManageController, :logout
    get "/app", ManageController, :index
    post "/app/projects", ManageController, :create
    get "/app/projects/:id", ManageController, :show
    post "/app/projects/:id/rotate", ManageController, :rotate
    post "/app/projects/:id/delete", ManageController, :delete
    post "/app/projects/:id/threads/:thread_id/delete", ManageController, :delete_thread
  end

  scope "/api/projects", FluentlyWeb do
    pipe_through :api
    options "/:id/*path", FeedbackAPIController, :options
    post "/:id/sessions", FeedbackAPIController, :session
    get "/:id/comments", FeedbackAPIController, :index
    post "/:id/comments", FeedbackAPIController, :create
    get "/:id/comments/:thread_id", FeedbackAPIController, :show
    post "/:id/comments/:thread_id/replies", FeedbackAPIController, :reply
    patch "/:id/comments/:thread_id", FeedbackAPIController, :update
  end

  # Other scopes may use custom stacks.
  # scope "/api", FluentlyWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:fluently, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FluentlyWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end

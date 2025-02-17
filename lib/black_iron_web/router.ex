defmodule BlackIronWeb.Router do
  use BlackIronWeb, :router

  import BlackIronWeb.UserAuth

  @host Application.compile_env!(:black_iron, [BlackIronWeb.Endpoint, :url, :host])

  @content_security_policy (case Application.compile_env!(:black_iron, :env) do
                              :prod ->
                                "default-src 'self' 'unsafe-eval' 'unsafe-inline';" <>
                                  "child-src 'self';" <>
                                  "connect-src wss://#{@host} https://#{@host} blob:;" <>
                                  "img-src 'self' blob: data:;" <>
                                  "font-src data:;"

                              _ ->
                                "default-src 'self' 'unsafe-eval' 'unsafe-inline';" <>
                                  "child-src 'self';" <>
                                  "connect-src ws://#{@host}:* http://#{@host}:* blob:;" <>
                                  "img-src 'self' blob: data:;" <>
                                  "font-src data:;"
                            end)

  pipeline :browser do
    plug :accepts, ["html", "json"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BlackIronWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" => @content_security_policy
    }

    plug :fetch_current_user
    plug :put_current_route
    plug BlackIronWeb.Plugs.Locale, "en"
    plug :check_ajax_request
    plug :put_user_token
    plug :lit_ssr_content
  end

  defp put_current_route(conn, _) do
    case Phoenix.Router.route_info(BlackIronWeb.Router, "GET", current_path(conn), "any") do
      :error -> conn
      info -> assign(conn, :current_route, info.route)
    end
  end

  defp check_ajax_request(conn, _) do
    if get_req_header(conn, "ajax-it") == ["true"] do
      conn
      |> assign(:ajax, true)
      |> put_root_layout(html: false)
      |> put_layout(html: false)
    else
      conn
    end
  end

  defp lit_ssr_content(conn, _) do
    register_before_send(conn, fn conn ->
      {:ok, rendered} = BlackIron.LitSSRWorker.prerender_html(conn.resp_body |> to_string())
      resp(conn, conn.status, rendered)
    end)
  end

  defp put_user_token(conn, _) do
    if current_user = conn.assigns[:current_user] do
      token = Phoenix.Token.sign(conn, "black iron user token", current_user.id)
      assign(conn, :user_token, token)
    else
      conn
    end
  end

  defp sidebar(conn, _) do
    conn
    |> put_root_layout(html: {BlackIronWeb.Layouts, :sidebar})
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # This is a special pipeline used as a tag for feeding the service worker
  # the routes we want to precache.
  pipeline :service_worker do
    plug :set_preload_flag
  end

  defp set_preload_flag(conn, _) do
    if get_req_header(conn, "x-preload") == ["true"] do
      conn
      |> assign(:preload, true)
      # Also remove session stuff
      |> assign(:current_user, nil)
      |> assign(:user_token, nil)
    else
      conn
    end
  end

  pipeline :app do
    plug :put_layout, html: {BlackIronWeb.Layouts, :app}
  end

  pipeline :site do
    plug :put_layout, html: {BlackIronWeb.Layouts, :site}
  end

  scope "/", BlackIronWeb do
    pipe_through [:browser, :site, :service_worker]

    get "/", PageController, :home
    get "/offline", OfflineController, :site
  end

  scope "/", BlackIronWeb do
    pipe_through [:api, :app]

    get "/offline/static_paths", OfflineController, :static_paths
    get "/offline/app_paths", OfflineController, :app_paths
  end

  # scope "/api", BlackIronWeb do
  #   pipe_through [:api, :api_auth]

  #   # Nothing here yet.
  # end

  # defp api_auth(conn, _) do
  #   with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
  #        {:ok, user_id} <-
  #          Phoenix.Token.verify(conn, "black iron user token", token, max_age: 1_209_600) do
  #     assign(conn, :current_user, BlackIron.Accounts.get_user!(user_id))
  #   else
  #     _ -> send_resp(conn, 401, "{\"error\": \"Unauthorized\"}")
  #   end
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:black_iron, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BlackIronWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", BlackIronWeb do
    pipe_through [:browser, :site, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
    get "/users/log_in", UserSessionController, :new
    post "/users/log_in", UserSessionController, :create
    get "/users/reset_password", UserResetPasswordController, :new
    post "/users/reset_password", UserResetPasswordController, :create
    get "/users/reset_password/:token", UserResetPasswordController, :edit
    put "/users/reset_password/:token", UserResetPasswordController, :update
  end

  scope "/", BlackIronWeb do
    pipe_through [:browser, :site, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm_email/:token", UserSettingsController, :confirm_email
  end

  scope "/", BlackIronWeb do
    pipe_through [:browser, :site]

    post "/theme", ThemeController, :update

    get "/users/log_out", UserSessionController, :delete
    delete "/users/log_out", UserSessionController, :delete
    get "/users/confirm", UserConfirmationController, :new
    post "/users/confirm", UserConfirmationController, :create
    get "/users/confirm/:token", UserConfirmationController, :edit
    post "/users/confirm/:token", UserConfirmationController, :update
  end

  scope "/play", BlackIronWeb do
    pipe_through [:app, :browser, :service_worker]

    get "/", PlayController, :show
    get "/campaigns", CampaignsController, :index
    get "/campaigns/:campaign_pid/:slug", CampaignsController, :show

    scope "/campaigns/:campaign_pid/:cslug" do
      get "/journals/:journal_pid/:slug", JournalsController, :show
      get "/journals", JournalsController, :index
      get "/worlds", WorldsController, :index
      get "/worlds/:world_pid/:slug", WorldsController, :show
      get "/npcs", NPCsController, :index
      get "/npcs/:npc_pid/:slug", NPCsController, :show
      get "/lore", LoreController, :index
      get "/lore/:lore_pid/:slug", LoreController, :show
      get "/tracks", TracksController, :index
      get "/tracks/:track_pid/:slug", TracksController, :show
      get "/pcs", PCsController, :index
      get "/pcs/:pc_pid/:slug", PCsController, :show

      scope "/sidebar" do
        pipe_through [:sidebar]

        get "/", SidebarController, :show
        get "/journals", JournalsController, :index
        get "/worlds", WorldsController, :index
        get "/worlds/:world_pid/:slug", WorldsController, :show
        get "/npcs", NPCsController, :index
        get "/npcs/:npc_pid/:slug", NPCsController, :show
        get "/lore", LoreController, :index
        get "/lore/:lore_pid/:slug", LoreController, :show
        get "/tracks", TracksController, :index
        get "/tracks/:track_pid/:slug", TracksController, :show
        get "/pcs", PCsController, :index
        get "/pcs/new", PCsController, :new
        get "/pcs/:pc_pid/:slug", PCsController, :show
      end
    end
  end

  scope "/play", BlackIronWeb do
    pipe_through [:app, :browser, :require_authenticated_user]

    post "/campaigns", CampaignsController, :create

    scope "/campaigns/:campaign_pid/:cslug" do
      post "/pcs", PCsController, :insert_or_update
    end
  end
end

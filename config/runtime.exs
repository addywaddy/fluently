import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/fluently start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :fluently, FluentlyWeb.Endpoint, server: true
end

config :fluently, FluentlyWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :fluently, FluentlyWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/fluently_web/router\.ex$"E,
        ~r"lib/fluently_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  if dsn = System.get_env("SENTRY_DSN") do
    config :sentry, dsn: dsn
  end

  config :sentry, release: System.get_env("KAMAL_VERSION") || System.get_env("SENTRY_RELEASE")

  database_path = System.fetch_env!("DATABASE_PATH")

  unless Path.type(database_path) == :absolute do
    raise "DATABASE_PATH must be an absolute path on persistent local storage"
  end

  config :fluently, Fluently.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "5"))

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :fluently, :canonical_feedback_origin, "https://" <> host

  config :fluently, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :fluently, FluentlyWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :fluently, FluentlyWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :fluently, FluentlyWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  config :fluently, Fluently.Mailer,
    adapter: Swoosh.Adapters.Resend,
    api_key: System.fetch_env!("RESEND_API_KEY")

  config :fluently, :mail_from, {"Fluently", System.fetch_env!("MAIL_FROM")}
end

# Toggle the first-party landing feedback widget and its cookie API.
config :fluently, :demo_enabled, System.get_env("FLUENTLY_DEMO_ENABLED", "true") == "true"

# First-party feedback goes to the owner's shared project. An absent project fails closed.
if config_env() != :test do
  config :fluently,
         :feedback_project_id,
         System.get_env("FLUENTLY_PROJECT_ID") ||
           if(config_env() == :prod,
             do: "bfef5446-e12f-40d1-96db-dced5bf805e1",
             else: "de78e976-1134-42b3-ad66-ac96136c3d31"
           )
end

# Resolve the explicitly trusted Docker proxy at boot, never from request input.
# Restart/redeploy the app after replacing the proxy container so this stays current.
if proxy = System.get_env("TRUSTED_PROXY_HOST") do
  case :inet.getaddrs(String.to_charlist(proxy), :inet) do
    {:ok, addresses} when addresses != [] ->
      config :fluently, :trusted_proxy_ips, addresses

    _ ->
      raise "TRUSTED_PROXY_HOST could not be resolved"
  end
end

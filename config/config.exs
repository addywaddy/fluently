# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :fluently,
  ecto_repos: [Fluently.Repo],
  generators: [timestamp_type: :utc_datetime]

# Reserve the SQLite writer before read/modify/write transactions. Keep these short.
config :fluently, Fluently.Repo,
  journal_mode: :wal,
  foreign_keys: :on,
  synchronous: :full,
  busy_timeout: 5000,
  default_transaction_mode: :immediate

# Configure the endpoint
config :fluently, FluentlyWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FluentlyWeb.ErrorHTML, json: FluentlyWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Fluently.PubSub,
  live_view: [signing_salt: "3b1aySrL"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :fluently, Fluently.Mailer, adapter: Swoosh.Adapters.Local
config :fluently, :mail_from, {"Fluently", "hello@fluently.test"}

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  fluently: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Runtime DSNs are enabled only for production. Test reports are collected locally.
config :sentry,
  dsn: nil,
  client: Fluently.Sentry.HTTPClient,
  before_send: {Fluently.Sentry.Privacy, :before_send},
  in_app_module_allow_list: [Fluently, FluentlyWeb]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

config :phoenix, :filter_parameters, [
  "password",
  "key",
  "token",
  "authorization",
  "body",
  "name",
  "data_url",
  "code",
  "verifier",
  "state",
  "return_to",
  "external_ref"
]

config :esbuild, :embed,
  args: ~w(embed/embed.js --bundle --target=es2022 --minify --outfile=../priv/static/embed.js),
  cd: Path.expand("../assets", __DIR__)

config :esbuild, :extension,
  args:
    ~w(extension/content.js --bundle --target=chrome120,firefox128,safari17 --minify --outfile=extension/dist/content.js),
  cd: Path.expand("..", __DIR__)

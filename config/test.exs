use Mix.Config

config :beepbop, BeepBop.TestRepo,
  username: "avia",
  password: "scoobie",
  database: "beepbop",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

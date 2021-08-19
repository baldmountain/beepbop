defmodule BeepBop.TestRepo do
  use Ecto.Repo,
    otp_app: :beepbop,
    adapter: Ecto.Adapters.Postgres
end

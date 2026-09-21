defmodule Fluently.Feedback.Actor do
  @moduledoc "A registered user authorized to act on a project."

  @enforce_keys [:project_id, :user_id, :name]
  defstruct [:project_id, :user_id, :name, :email, account_member: true, kind: "account"]
end

defmodule Fluently.Accounts.AccountMembershipTest do
  use Fluently.DataCase, async: true

  alias Fluently.Accounts.AccountMembership

  test "accepts the supported organization roles" do
    for role <- AccountMembership.roles() do
      changeset =
        AccountMembership.changeset(%AccountMembership{}, %{
          account_id: Ecto.UUID.generate(),
          user_id: Ecto.UUID.generate(),
          role: role
        })

      assert changeset.valid?
    end
  end

  test "rejects role escalation values" do
    changeset =
      AccountMembership.changeset(%AccountMembership{}, %{
        account_id: Ecto.UUID.generate(),
        user_id: Ecto.UUID.generate(),
        role: "ownerish"
      })

    refute changeset.valid?
    assert %{role: ["is invalid"]} = errors_on(changeset)
  end

  test "owner and admin predicates reflect effective roles" do
    assert AccountMembership.owner?(%AccountMembership{role: "owner"})
    refute AccountMembership.owner?(%AccountMembership{role: "admin"})
    assert AccountMembership.admin?(%AccountMembership{role: "owner"})
    assert AccountMembership.admin?(%AccountMembership{role: "admin"})
    refute AccountMembership.admin?(%AccountMembership{role: "member"})
  end
end

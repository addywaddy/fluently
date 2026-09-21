defmodule Fluently.Feedback.ProjectMembershipTest do
  use Fluently.DataCase, async: true

  alias Fluently.Feedback.ProjectMembership

  test "requires a project and user" do
    changeset = ProjectMembership.changeset(%ProjectMembership{}, %{})
    refute changeset.valid?
    assert %{project_id: ["can't be blank"], user_id: ["can't be blank"]} = errors_on(changeset)
  end

  test "accepts a project assignment" do
    changeset =
      ProjectMembership.changeset(%ProjectMembership{}, %{
        project_id: Ecto.UUID.generate(),
        user_id: Ecto.UUID.generate()
      })

    assert changeset.valid?
  end
end

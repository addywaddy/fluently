defmodule FluentlyWeb.ReviewVisibilityTest do
  use FluentlyWeb.ConnCase, async: false
  alias Fluently.{Accounts, AccountReviews, Feedback, ProjectAccess, Repo, Threads}
  import Fluently.FeedbackFixtures

  setup do
    {:ok, {account, login}} =
      Accounts.register(nil, %{
        name: "Jane Smith",
        email: "jane@example.test",
        password: "a long enough test password"
      })

    workspace = Feedback.workspace(account.workspace_id)

    {:ok, project, keys} =
      Feedback.create_project(workspace, %{name: "Site", origin: "https://example.com"})

    project = Repo.update!(Ecto.Changeset.change(project, public_feedback: true))
    previous = Application.get_env(:fluently, :feedback_project_id)
    Application.put_env(:fluently, :feedback_project_id, project.id)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:fluently, :feedback_project_id, previous),
        else: Application.delete_env(:fluently, :feedback_project_id)
    end)

    {:ok, guest_token, guest} = Feedback.start_review(project, keys.review, "Guest")

    %{
      account: account,
      login: login,
      project: project,
      guest: guest,
      guest_token: guest_token,
      keys: keys
    }
  end

  defp payload(project), do: Map.put(attrs(), "page", project.origin <> "/")

  defp api(c, token, params) do
    build_conn()
    |> put_req_header("origin", c.project.origin)
    |> put_req_header("authorization", "Bearer " <> token)
    |> get("/api/projects/#{c.project.id}/comments", params)
    |> json_response(200)
  end

  defp member(c) do
    verifier = Feedback.secret()

    {:ok, code} =
      AccountReviews.issue(
        c.project,
        c.account,
        Base.url_encode64(Feedback.hash(verifier), padding: false)
      )

    {:ok, %{token: token, identity: identity}} =
      AccountReviews.exchange(c.project, code, verifier)

    {token, identity}
  end

  defp landing(c, params) do
    %{build_conn() | host: "example.com", scheme: :https}
    |> init_test_session(account_token: c.login)
    |> get("/demo/comments", params)
    |> json_response(200)
  end

  test "member can toggle own and all threads; filtering happens before pagination", c do
    {token, identity} = member(c)
    for _ <- 1..101, do: assert({:ok, _} = Threads.create(c.project, c.guest, payload(c.project)))
    {:ok, own} = Threads.create(c.project, identity, payload(c.project))
    assert length(api(c, token, %{view: "all"})["data"]) == 100
    mine = api(c, token, %{view: "mine"})
    assert Enum.map(mine["data"], & &1["id"]) == [own.id]
    assert mine["next_offset"] == nil
    assert mine["identity"] == %{"name" => "Jane Smith", "kind" => "account"}

    assert Enum.map(api(c, c.guest_token, %{view: "all", offset: "100"})["data"], & &1["id"]) != [
             own.id
           ]

    refute Enum.any?(
             api(c, c.guest_token, %{view: "all", offset: "100"})["data"],
             &(&1["id"] == own.id)
           )

    assert {:ok, _} = Threads.status(c.project, own.id, "resolved")
    assert api(c, token, %{view: "mine", status: "open"})["data"] == []
    assert length(api(c, token, %{view: "mine", status: "resolved"})["data"]) == 1
    assert api(c, c.keys.api, %{view: "mine"})["data"] == []
  end

  test "landing account reviews exclude guest authorship and empty identity does not mean all",
       c do
    {:ok, guest_thread} = Threads.create(c.project, c.guest, payload(c.project))
    assert landing(c, %{view: "mine"})["data"] == []
    assert Enum.map(landing(c, %{view: "all"})["data"], & &1["id"]) == [guest_thread.id]

    {:ok, identity} =
      ProjectAccess.reviewer(Feedback.workspace(c.account.workspace_id), c.project)

    {:ok, own} = Threads.create(c.project, identity, payload(c.project))
    assert Enum.map(landing(c, %{view: "mine"})["data"], & &1["id"]) == [own.id]
    assert length(landing(c, %{view: "all"})["data"]) == 2

    stranger =
      %{build_conn() | host: "example.com", scheme: :https}
      |> get("/demo/comments", %{view: "all"})
      |> json_response(200)

    assert stranger["data"] == []
  end
end

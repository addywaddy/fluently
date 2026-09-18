defmodule Fluently.Feedback do
  @moduledoc "Tenant-scoped project credentials and feedback operations. Public IDs never authorize access."
  import Ecto.Query
  import Ecto.Changeset
  alias Fluently.Repo
  alias Fluently.Feedback.{Workspace, Project, ProjectUser}

  def secret, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  def hash(value) when is_binary(value), do: :crypto.hash(:sha256, value)
  def hash(_), do: hash("")

  def valid_secret?(value, digest) when is_binary(value) and is_binary(digest),
    do: Plug.Crypto.secure_compare(hash(value), digest)

  def valid_secret?(_, _), do: false

  def create_workspace(name) do
    key = secret()

    result =
      %Workspace{access_hash: hash(key)}
      |> cast(%{name: name}, [:name])
      |> validate_required([:name])
      |> validate_length(:name, max: 100)
      |> Repo.insert()

    case result do
      {:ok, workspace} -> {:ok, workspace, key}
      error -> error
    end
  end

  def authenticate_owner(key), do: Repo.get_by(Workspace, access_hash: hash(key))
  def workspace(id), do: safe_get(Workspace, id)

  def projects(workspace),
    do:
      Repo.all(
        from p in Project, where: p.workspace_id == ^workspace.id, order_by: [desc: p.inserted_at]
      )

  def project(workspace, id),
    do:
      with(
        %Project{workspace_id: owner} = p <- project(id),
        true <- owner == workspace.id,
        do: p,
        else: (_ -> nil)
      )

  def project(id), do: safe_get(Project, id)

  def create_project(workspace, attrs) do
    credentials = %{review: secret(), api: secret()}

    changeset =
      %Project{
        workspace_id: workspace.id,
        review_hash: hash(credentials.review),
        api_hash: hash(credentials.api),
        review_expires_at: DateTime.add(DateTime.utc_now(), 14, :day)
      }
      |> cast(attrs, [:name, :origin])
      |> validate_required([:name, :origin])
      |> validate_length(:name, max: 100)
      |> validate_change(:origin, fn :origin, value ->
        if valid_origin?(value),
          do: [],
          else: [origin: "must be an HTTPS origin without a path (HTTP allowed on localhost)"]
      end)

    case Repo.insert(changeset) do
      {:ok, p} -> {:ok, p, credentials}
      error -> error
    end
  end

  def rotate_project(%Workspace{} = workspace, id) do
    case project(workspace, id) do
      nil ->
        {:error, :not_found}

      p ->
        credentials = %{review: secret(), api: secret()}

        {:ok, p} =
          p
          |> change(
            review_hash: hash(credentials.review),
            api_hash: hash(credentials.api),
            review_expires_at: DateTime.add(DateTime.utc_now(), 14, :day),
            credential_version: p.credential_version + 1
          )
          |> Repo.update()

        {:ok, p, credentials}
    end
  end

  def delete_project(workspace, id) do
    case project(workspace, id) do
      nil ->
        {:error, :not_found}

      p ->
        Repo.transaction(fn ->
          Repo.delete_all(from t in Fluently.Feedback.Thread, where: t.project_id == ^p.id)
          Repo.delete!(p)
        end)
    end
  end

  def create_project_user(project, attrs, user_id \\ nil) do
    Repo.transaction(fn ->
      changeset =
        %ProjectUser{project_id: project.id, user_id: user_id}
        |> cast(attrs, [:name, :kind, :external_id])
        |> validate_required([:name])
        |> validate_length(:name, max: 80)
        |> validate_length(:external_id, max: 200)

      if not changeset.valid?, do: Repo.rollback(changeset)
      user_id = user_id || Repo.insert!(%Fluently.Accounts.User{}).id

      case changeset |> put_change(:user_id, user_id) |> Repo.insert() do
        {:ok, identity} -> identity
        {:error, error} -> Repo.rollback(error)
      end
    end)
  end

  def start_review(p, key, name, external_ref \\ nil)

  def start_review(p, key, name, external_ref)
      when is_nil(external_ref) or is_binary(external_ref) do
    if valid_secret?(key, p.review_hash) and
         DateTime.compare(p.review_expires_at, DateTime.utc_now()) == :gt do
      if valid_external_ref?(external_ref) do
        create_project_user(p, %{
          name: name,
          external_id: external_ref,
          kind: if(external_ref, do: "pseudonymous", else: "guest")
        })
        |> case do
          {:ok, reviewer} ->
            {:ok,
             Phoenix.Token.sign(FluentlyWeb.Endpoint, "review-session-v1", %{
               project: p.id,
               reviewer: reviewer.id,
               version: p.credential_version
             }), reviewer}

          error ->
            error
        end
      else
        {:error, :invalid_reference}
      end
    else
      {:error, :unauthorized}
    end
  end

  def start_review(_, _, _, _), do: {:error, :invalid_reference}
  defp valid_external_ref?(nil), do: true

  defp valid_external_ref?(value),
    do: byte_size(value) in 1..200 and Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, value)

  def authorize(p, token) do
    case Fluently.AccountReviews.authorize(p, token) do
      {:ok, identity} -> {:ok, identity}
      _ -> authorize_guest(p, token)
    end
  end

  defp authorize_guest(p, token) do
    with {:ok, %{project: id, reviewer: rid, version: version}} <-
           Phoenix.Token.verify(FluentlyWeb.Endpoint, "review-session-v1", token || "",
             max_age: 86_400
           ),
         true <- id == p.id and version == p.credential_version,
         true <- DateTime.compare(p.review_expires_at, DateTime.utc_now()) == :gt,
         %ProjectUser{project_id: ^id} = reviewer <- safe_get(ProjectUser, rid) do
      {:ok, reviewer}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def valid_origin?(value) when is_binary(value) do
    with {:ok, uri} <- URI.new(value) do
      uri.scheme in ["https", "http"] and is_binary(uri.host) and uri.host != "" and
        is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment) and
        uri.path in [nil, ""] and
        (uri.scheme == "https" or uri.host in ["localhost", "127.0.0.1", "[::1]"]) and
        URI.to_string(%{uri | path: nil}) == value
    else
      _ -> false
    end
  end

  def valid_origin?(_), do: false

  defp safe_get(schema, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get(schema, id)
      _ -> nil
    end
  end
end

defmodule Fluently.Snapshots do
  @moduledoc "Small, immutable PNG attachments. Access always goes through the project boundary."
  import Ecto.Query
  alias Fluently.{Repo, Threads}
  alias Fluently.Feedback.{Reviewer, Snapshot}

  @max_bytes 204_800
  def attach(project, %Reviewer{project_id: pid} = reviewer, id, data) when pid == project.id do
    Repo.transaction(fn ->
      thread = Threads.get(project, id) || Repo.rollback(:not_found)
      if thread.reviewer_id != reviewer.id, do: Repo.rollback(:not_found)

      {image, width, height} =
        case decode(data) do
          {:ok, result} -> result
          _ -> Repo.rollback(:invalid_image)
        end

      %Snapshot{thread_id: thread.id, image: image, width: width, height: height}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.unique_constraint(:thread_id, name: :feedback_snapshots_pkey)
      |> Repo.insert(on_conflict: :nothing, conflict_target: :thread_id, log: false)
      |> case do
        {:ok, _} -> :ok
        {:error, error} -> Repo.rollback(error)
      end
    end)
  end

  def attach(_, _, _, _), do: {:error, :not_found}

  def get(project, id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      Repo.one(
        from s in Snapshot,
          join: t in Fluently.Feedback.Thread,
          on: t.id == s.thread_id,
          where: t.project_id == ^project.id and s.thread_id == ^id
      )
    else
      _ -> nil
    end
  end

  def serialize(snapshot) do
    %{
      data_url: "data:image/png;base64," <> Base.encode64(snapshot.image),
      width: snapshot.width,
      height: snapshot.height,
      created_at: snapshot.inserted_at
    }
  end

  # Only bounded raster PNGs, never SVG/HTML or caller-supplied MIME types.
  defp decode("data:image/png;base64," <> encoded) when byte_size(encoded) <= 273_068 do
    with {:ok, image} <- Base.decode64(encoded),
         true <- byte_size(image) <= @max_bytes,
         <<137, 80, 78, 71, 13, 10, 26, 10, 13::32, "IHDR", width::32, height::32, 8, color, 0, 0,
           0, crc::32, rest::binary>> <- image,
         true <- crc == :erlang.crc32(<<"IHDR", width::32, height::32, 8, color, 0, 0, 0>>),
         true <- color in [2, 6] and width in 1..1200 and height in 1..1200,
         true <- valid_chunks?(rest, false) do
      {:ok, {image, width, height}}
    else
      _ -> {:error, :invalid_image}
    end
  end

  defp decode(_), do: {:error, :invalid_image}

  defp valid_chunks?(<<0::32, "IEND", crc::32>>, seen_data),
    do: seen_data and crc == :erlang.crc32("IEND")

  defp valid_chunks?(<<length::32, type::binary-size(4), rest::binary>>, seen_data)
       when length <= @max_bytes do
    case rest do
      <<data::binary-size(^length), crc::32, tail::binary>> ->
        type in ["IDAT", "sRGB", "gAMA", "cHRM", "pHYs"] and
          crc == :erlang.crc32(type <> data) and
          valid_chunks?(tail, seen_data or type == "IDAT")

      _ ->
        false
    end
  end

  defp valid_chunks?(_, _), do: false
end

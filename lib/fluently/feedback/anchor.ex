defmodule Fluently.Feedback.Anchor do
  @moduledoc "Versioned platform envelope. Only explicit, bounded context fields cross the API boundary."
  def normalize(
        %{
          "version" => 1,
          "platform" => "web",
          "type" => "dom",
          "target" => target,
          "point" => point
        } = anchor
      )
      when is_map(target) and is_map(point) do
    with true <- text?(target["tag"], 30) and target["tag"] =~ ~r/^[a-z][a-z0-9-]*$/,
         true <- text?(target["selector"], 1000),
         true <-
           Enum.all?(
             ["feedback_id", "id", "role", "label", "text"],
             &optional_text?(target[&1], 160)
           ),
         true <- number?(point["x"], 0, 1) and number?(point["y"], 0, 1),
         true <- map_size(anchor) == 5 do
      {:ok,
       %{
         "version" => 1,
         "platform" => "web",
         "type" => "dom",
         "target" => Map.take(target, ~w(tag selector feedback_id id role label text)),
         "point" => Map.take(point, ~w(x y))
       }}
    else
      _ -> {:error, :invalid_anchor}
    end
  end

  def normalize(_), do: {:error, :invalid_anchor}

  def context(
        %{"viewport" => %{"width" => w, "height" => h}, "scroll" => %{"x" => x, "y" => y}} = value
      ) do
    if number?(w, 1, 30000) and number?(h, 1, 30000) and number?(x, -1_000_000, 1_000_000) and
         number?(y, 0, 1_000_000) and optional_text?(value["browser"], 80) do
      {:ok,
       %{
         "viewport" => %{"width" => w, "height" => h},
         "scroll" => %{"x" => x, "y" => y},
         "browser" => value["browser"]
       }}
    else
      {:error, :invalid_context}
    end
  end

  def context(_), do: {:error, :invalid_context}

  defp text?(value, max),
    do: is_binary(value) and String.length(value) > 0 and String.length(value) <= max

  defp optional_text?(nil, _), do: true
  defp optional_text?(value, max), do: is_binary(value) and String.length(value) <= max
  defp number?(value, low, high), do: is_number(value) and value >= low and value <= high
end

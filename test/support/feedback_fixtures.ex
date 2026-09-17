defmodule Fluently.FeedbackFixtures do
  def snapshot(width \\ 1, height \\ 1) do
    # Real RGBA PNGs, including incompressible images to exercise upload limits.
    rows = for _ <- 1..height, into: <<>>, do: <<0>> <> :crypto.strong_rand_bytes(width * 4)

    "data:image/png;base64," <>
      Base.encode64(
        <<137, 80, 78, 71, 13, 10, 26, 10>> <>
          png_chunk("IHDR", <<width::32, height::32, 8, 6, 0, 0, 0>>) <>
          png_chunk("IDAT", :zlib.compress(rows)) <>
          png_chunk("IEND", <<>>)
      )
  end

  defp png_chunk(type, data),
    do: <<byte_size(data)::32, type::binary, data::binary, :erlang.crc32(type <> data)::32>>

  def attrs do
    %{
      "body" => "Change the label",
      "page" => "https://example.com/checkout?secret=private#token",
      "anchor" => %{
        "version" => 1,
        "platform" => "web",
        "type" => "dom",
        "target" => %{"tag" => "button", "selector" => "#checkout", "feedback_id" => "checkout"},
        "point" => %{"x" => 0.5, "y" => 0.5}
      },
      "context" => %{
        "viewport" => %{"width" => 1440, "height" => 900},
        "scroll" => %{"x" => 0, "y" => 10},
        "browser" => "Safari",
        "cookies" => "must not persist"
      }
    }
  end
end

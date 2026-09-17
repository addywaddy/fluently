defmodule Fluently.FeedbackFixtures do
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

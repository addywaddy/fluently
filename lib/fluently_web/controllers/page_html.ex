defmodule FluentlyWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use FluentlyWeb, :html

  embed_templates "page_html/*"
end

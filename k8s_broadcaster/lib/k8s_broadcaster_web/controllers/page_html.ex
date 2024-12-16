defmodule K8sBroadcasterWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use K8sBroadcasterWeb, :html

  embed_templates "page_html/*"
end

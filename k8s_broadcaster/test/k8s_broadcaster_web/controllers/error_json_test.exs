defmodule K8sBroadcasterWeb.ErrorJSONTest do
  use K8sBroadcasterWeb.ConnCase, async: true

  test "renders 404" do
    assert K8sBroadcasterWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert K8sBroadcasterWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end

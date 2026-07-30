defmodule TaskyWeb.UploadControllerTest do
  use TaskyWeb.ConnCase, async: false

  test "upload responses carry restrictive security headers", %{conn: conn} do
    conn = get(conn, "/uploads/exams/1/#{Ecto.UUID.generate()}.png")

    assert response(conn, 404)
    assert get_resp_header(conn, "content-security-policy") == ["default-src 'none'; sandbox"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "cross-origin-resource-policy") == ["same-origin"]
  end

  test "browser pages carry the content security policy", %{conn: conn} do
    conn = get(conn, "/")

    assert [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "default-src 'self'"
    assert csp =~ "script-src 'self'"
    assert csp =~ "connect-src 'self' ws: wss:"
  end
end

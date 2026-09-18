defmodule FluentlyWeb.ClientIPTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  alias FluentlyWeb.ClientIP
  @proxy {172, 18, 0, 2}

  defp connection(peer, header) do
    %{Plug.Test.conn(:get, "/") | remote_ip: peer}
    |> put_req_header("x-forwarded-for", header)
  end

  test "direct clients cannot choose their rate-limit identity" do
    peer = {198, 51, 100, 10}
    conn = ClientIP.call(connection(peer, "203.0.113.2"), trusted: [@proxy])
    assert conn.remote_ip == peer
    assert ClientIP.call(connection(@proxy, "203.0.113.2"), trusted: []).remote_ip == @proxy
  end

  test "only the actual client appended by Kamal is trusted" do
    conn =
      ClientIP.call(connection(@proxy, "10.1.2.3, 172.18.0.2, 203.0.113.2"), trusted: [@proxy])

    assert conn.remote_ip == {203, 0, 113, 2}
    conn = ClientIP.call(connection(@proxy, "forged, 2001:db8::1"), trusted: [@proxy])
    assert conn.remote_ip == {8193, 3512, 0, 0, 0, 0, 0, 1}
  end

  test "malformed or absent nearest client fails closed to the proxy IP" do
    for header <- [
          "",
          "garbage",
          "203.0.113.1,",
          "203.0.113.1, unknown",
          "127.1",
          "203.0.113.1:1234",
          String.duplicate("x", 4097)
        ] do
      assert ClientIP.call(connection(@proxy, header), trusted: [@proxy]).remote_ip == @proxy
    end
  end

  test "visitors behind one proxy receive separate rate limit buckets" do
    a = ClientIP.call(connection(@proxy, "203.0.113.10"), trusted: [@proxy])
    b = ClientIP.call(connection(@proxy, "203.0.113.11"), trusted: [@proxy])
    key = make_ref()
    assert Fluently.RateLimit.allow?({key, a.remote_ip}, 1)
    refute Fluently.RateLimit.allow?({key, a.remote_ip}, 1)
    assert Fluently.RateLimit.allow?({key, b.remote_ip}, 1)
  end
end

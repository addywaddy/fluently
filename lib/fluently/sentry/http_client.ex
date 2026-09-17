defmodule Fluently.Sentry.HTTPClient do
  @moduledoc false
  @behaviour Sentry.HTTPClient

  @impl true
  def post(url, headers, body) do
    case Req.post(url,
           headers: headers,
           body: body,
           decode_body: false,
           retry: false,
           redirect: false,
           receive_timeout: 5_000
         ) do
      {:ok, response} ->
        headers = for {name, values} <- response.headers, value <- values, do: {name, value}
        {:ok, response.status, headers, response.body}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

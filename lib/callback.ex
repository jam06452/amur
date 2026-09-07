defmodule Amur.Callback do
  @moduledoc """
  Behaviour for handling the result of an OAuth flow.

  Implement both callbacks in the module configured by `:on_success` and
  `:on_failure`. The success callback receives the normalized user and OAuth
  token, while the failure callback receives the reason the flow failed.
  """

  @callback on_success(Plug.Conn.t(), %{user: map(), token: map()}) :: Plug.Conn.t()
  @callback on_failure(Plug.Conn.t(), term()) :: Plug.Conn.t()
end

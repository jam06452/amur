defmodule Amur.Telemetry do
  @moduledoc false

  # Emits the `:telemetry` spans that instrument Amur's OAuth flow.
  #
  # Two spans are emitted, one per phase of the flow:
  #
  #   * `[:amur, :request, ...]` - starting an authorization request
  #   * `[:amur, :callback, ...]` - completing the provider callback
  #
  # Each span is delegated to `:telemetry.span/3`, so it produces the usual
  # `:start`, `:stop` and `:exception` events with the standard measurements.
  # The span covers only Amur's own OAuth work: resolving the provider, calling
  # the Assent strategy, and normalizing the user. The host application's
  # `:on_success` and `:on_failure` callbacks run outside the span, so their
  # duration and any exceptions they raise are not attributed to Amur.
  #
  # Metadata never carries the connection, the session, tokens, credentials, or
  # the raw user map. The provider is reported as the resolved provider atom, or
  # `nil` when the request names a provider that is not configured or does not
  # resolve, so metric labels stay bounded and a request cannot grow the VM atom
  # table.
  #
  # Failure reasons are reduced to a small set of categories before they are
  # emitted; the raw term is never included. See `sanitize_reason/1`.

  @doc """
  Runs `fun` inside a span, emitting the `:start`, `:stop` and `:exception`
  events for `event_prefix`.

  `fun` must return `{result, stop_metadata}`, matching `:telemetry.span/3`.
  `start_metadata` is emitted with the `:start` event; `stop_metadata` is merged
  with the base metadata for the `:stop` and `:exception` events.

  Exceptions raised by `fun` are re-raised unchanged, but with their stacktrace
  scrubbed of function arguments, so a crash cannot leak provider configuration
  through the `:exception` metadata.
  """
  def span(event_prefix, start_metadata, fun) do
    :telemetry.span(event_prefix, start_metadata, fn ->
      {result, stop_metadata} = guarded(fun)

      # `:telemetry.span/3` does not carry the start metadata into the stop
      # event, so merge it here. The start metadata is emitted as-is, and the
      # stop and exception events carry the union of both.
      {result, Map.merge(start_metadata, stop_metadata)}
    end)
  end

  # Runs `fun`, re-raising any error, throw or exit with a scrubbed stacktrace.
  #
  # `catch kind, reason` is used rather than `rescue` so that all three failure
  # kinds are covered and the original reason is preserved: the host
  # application's error handling must see exactly the failure it would have seen
  # without telemetry. Only the stacktrace is altered, and only to drop the
  # argument lists that `:telemetry.span/3` would otherwise embed in the
  # `:exception` metadata.
  defp guarded(fun) do
    fun.()
  catch
    kind, reason ->
      :erlang.raise(kind, reason, scrub(__STACKTRACE__))
  end

  # Replaces each frame's argument list with its arity. Only the top frame
  # carries arguments, but the pattern is written to handle any frame that does.
  # Module, function, arity and location are preserved, so debugging is barely
  # affected.
  defp scrub(stacktrace) do
    Enum.map(stacktrace, fn
      {module, function, args, location} when is_list(args) ->
        {module, function, length(args), location}

      frame ->
        frame
    end)
  end

  @doc """
  Reduces a failure reason to a bounded category for telemetry metadata.

  The raw reason is deliberately not emitted: strategy errors may embed HTTP
  response bodies, and handlers routinely log telemetry metadata wholesale.
  Unknown reasons fall back to `:provider_error`.
  """
  def sanitize_reason(:unknown_provider), do: :unknown_provider
  def sanitize_reason(:invalid_session_params), do: :invalid_session_params

  def sanitize_reason({:error, reason}), do: sanitize_reason(reason)

  # Assent reports a state mismatch as an `Assent.CallbackCSRFError`.
  def sanitize_reason(%{__struct__: Assent.CallbackCSRFError}), do: :state_mismatch

  # The provider declined the request, usually because the user cancelled. Assent
  # carries the OAuth error code in `:error` on a `CallbackError`.
  def sanitize_reason(%{__struct__: Assent.CallbackError, error: "access_denied"}),
    do: :access_denied

  def sanitize_reason(%{__struct__: Assent.CallbackError}), do: :provider_error

  # Transport-level failures, which are worth distinguishing from a provider
  # that answered with an error. Assent wraps every adapter failure (including
  # `Mint.TransportError`, `Mint.HTTPError` and `:timeout`) in this struct, so
  # matching it here covers all of them; the raw terms never reach Amur.
  def sanitize_reason(%{__struct__: Assent.ServerUnreachableError}), do: :network_error

  def sanitize_reason(_reason), do: :provider_error
end

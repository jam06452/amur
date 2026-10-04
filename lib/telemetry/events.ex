defmodule Amur.Telemetry.Events do
  @moduledoc """
  The `:telemetry` events emitted by Amur.

  Amur instruments its OAuth flow with `:telemetry`. Attach handlers to observe
  authorization requests and callbacks without Amur taking on any state or
  imposing a logging strategy on your application.

  This module is documentation only: it defines no functions. The event names,
  measurements and metadata described here are the public contract, and changes
  to them are treated as breaking changes.

  ## Events

  Two spans are emitted, one per phase of the flow:

    * `[:amur, :request, ...]` — starting an authorization request
      (`Amur.Controller.request/2`)
    * `[:amur, :callback, ...]` — completing the provider callback
      (`Amur.Controller.callback/2`)

  Each span produces the three standard `:telemetry` events:

  | Event | Measurements | Metadata |
  |---|---|---|
  | `[:amur, :request, :start]` | `system_time` | `provider` |
  | `[:amur, :request, :stop]` | `duration`, `monotonic_time` | `provider`, `strategy`, `result`, `reason` |
  | `[:amur, :request, :exception]` | `duration`, `monotonic_time` | `provider`, `strategy`, `kind`, `reason`, `stacktrace` |
  | `[:amur, :callback, :start]` | `system_time` | `provider` |
  | `[:amur, :callback, :stop]` | `duration`, `monotonic_time` | `provider`, `strategy`, `result`, `reason` |
  | `[:amur, :callback, :exception]` | `duration`, `monotonic_time` | `provider`, `strategy`, `kind`, `reason`, `stacktrace` |

  `duration` is in native time units, as produced by `System.monotonic_time/0`.
  `:telemetry.span/3` also adds a `telemetry_span_context` to the `:stop` and
  `:exception` metadata, which lets a handler correlate the events of one span.

  ## Metadata

  | Key | Description |
  |---|---|
  | `provider` | The resolved provider atom, such as `:github`, or `nil` when the request names a provider that is not configured. |
  | `strategy` | The Assent strategy module, present on `:stop` and `:exception` once the provider has resolved. |
  | `result` | `:ok` or `:error`, present on `:stop`. |
  | `reason` | A sanitized failure category, present on `:stop` when `result` is `:error`. See below. |
  | `kind`, `reason`, `stacktrace` | The failure details on `:exception`, matching `:telemetry.span/3`. |

  Metadata never includes the connection, the session, the OAuth token, the
  normalized user, or any provider credentials.

  ## Failure reasons

  `reason` on a `:stop` event is reduced to a bounded category rather than the
  raw error term, because strategy errors may embed HTTP response bodies and
  handlers routinely log telemetry metadata wholesale:

  | Category | Cause |
  |---|---|
  | `:unknown_provider` | The provider name is not configured. |
  | `:invalid_session_params` | The session had no handshake state, or the state was empty or malformed. |
  | `:state_mismatch` | The provider's `state` did not match the one stored in the session. |
  | `:access_denied` | The provider declined the request, usually because the user cancelled. |
  | `:provider_error` | Any other error returned by the provider or its strategy. |
  | `:network_error` | A transport-level failure reaching the provider. |

  ## The span boundary

  The span covers only Amur's own OAuth work: resolving the provider, calling
  the Assent strategy, and normalizing the user. Your `:on_success` and
  `:on_failure` callbacks run **outside** the span, so their duration is not
  attributed to Amur and an exception they raise is not reported as an Amur
  exception.

  ## Attaching a handler

      :telemetry.attach_many(
        "amur-logger",
        [
          [:amur, :request, :stop],
          [:amur, :callback, :stop]
        ],
        fn event, measurements, metadata, _config ->
          Logger.info(
            "\#{inspect(event)} provider=\#{inspect(metadata.provider)} " <>
              "result=\#{metadata.result} duration=\#{measurements.duration}"
          )
        end,
        nil
      )

  ## A note on `:exception` metadata

  The `:exception` event is intended for error reporting. Amur scrubs function
  arguments from the stacktrace before it is emitted, so provider configuration
  cannot leak through a crash. The `reason` term, however, is passed through
  unchanged so that your error handling sees the failure it would have seen
  without telemetry; it may embed values from the failing call. Do not log
  `:exception` metadata wholesale or forward it to a third party without
  filtering it first.
  """
end

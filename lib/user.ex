defmodule Amur.User do
  @moduledoc """
  Types for the normalized user passed to OAuth callbacks.

  Provider-specific fields may be included in addition to the common fields.
  """

  @typedoc """
  A user normalized by an `Amur.Provider`.

  `:provider` is always added by Amur before the success callback is invoked.
  The other common fields are optional because providers do not all expose the
  same information.
  """
  @type t :: %{
          required(:provider) => String.t(),
          optional(:uid) => String.t(),
          optional(:email) => String.t() | nil,
          optional(:name) => String.t() | nil,
          optional(:avatar) => String.t() | nil,
          optional(atom()) => term()
        }
end

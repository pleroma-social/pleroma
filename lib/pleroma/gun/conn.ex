# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Gun.Conn do
  @moduledoc """
  Struct for gun connection data
  """
  @type t :: %__MODULE__{
          conn: pid(),
          state: atom(),
          waiting_pids: [pid()],
          used: pos_integer()
        }

  defstruct conn: nil, state: :open, waiting_pids: [], used: 0
end

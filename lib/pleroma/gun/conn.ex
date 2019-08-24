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
          last_reference: pos_integer(),
          crf: float()
        }

  defstruct conn: nil,
            state: :open,
            waiting_pids: [],
            last_reference: :os.system_time(:second),
            crf: 1
end

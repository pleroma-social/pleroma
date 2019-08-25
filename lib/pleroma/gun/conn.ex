# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Gun.Conn do
  @moduledoc """
  Struct for gun connection data
  """
  @type gun_state :: :open | :up | :down
  @type conn_state :: :init | :active | :idle

  @type t :: %__MODULE__{
          conn: pid(),
          gun_state: gun_state(),
          waiting_pids: [pid()],
          conn_state: conn_state(),
          used_by: [pid()],
          last_reference: pos_integer(),
          crf: float()
        }

  defstruct conn: nil,
            gun_state: :open,
            waiting_pids: [],
            conn_state: :init,
            used_by: [],
            last_reference: :os.system_time(:second),
            crf: 1
end

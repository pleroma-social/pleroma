defmodule Pleroma.Helpers.ServerIPHelper do
  @moduledoc """
  Module tries to get server real ip address from system or makes request to the remote server.
  """

  # Taken from https://ipinfo.io/bogon
  @bogon_ranges [
                  "0.0.0.0/8",
                  "10.0.0.0/8",
                  "100.64.0.0/10",
                  "127.0.0.0/8",
                  "127.0.53.53/32",
                  "169.254.0.0/16",
                  "172.16.0.0/12",
                  "192.0.0.0/24",
                  "192.0.2.0/24",
                  "192.168.0.0/16",
                  "198.18.0.0/15",
                  "198.51.100.0/24",
                  "203.0.113.0/24",
                  "224.0.0.0/4",
                  "240.0.0.0/4",
                  "255.255.255.255/32"
                ]
                |> Enum.map(&InetCidr.parse/1)

  @spec real_ip() :: {:ok, String.t()} | {:error, term()}
  def real_ip do
    if Pleroma.Config.get(:env) == :prod do
      from_system() || from_remote_server()
    else
      {:ok, "127.0.0.1"}
    end
  end

  defp from_system do
    with {:ok, interfaces} <- :inet.getifaddrs(),
         {_name, addresses} <-
           Enum.find(interfaces, fn {_name, addresses} ->
             addr = Keyword.get(addresses, :addr)

             Enum.all?([:up, :broadcast, :running], &(&1 in addresses[:flags])) and
               not Enum.any?(@bogon_ranges, &InetCidr.contains?(&1, addr))
           end) do
      ip =
        addresses
        |> Keyword.get(:addr)
        |> :inet.ntoa()
        |> to_string()

      {:ok, ip}
    else
      _ -> nil
    end
  end

  defp from_remote_server do
    with {:ok, %{body: body}} <- Pleroma.HTTP.get("https://api.myip.com") do
      %{"ip" => ip} = Jason.decode!(body)
      {:ok, ip}
    end
  end
end

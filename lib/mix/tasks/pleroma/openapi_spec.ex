defmodule Mix.Tasks.Pleroma.OpenapiSpec do
  def run([path]) do
    spec = Pleroma.Web.ApiSpec.spec() |> Jason.encode!()
    File.write(path, spec)
  end
end

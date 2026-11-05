tag = System.fetch_env!("RELEASE_TAG")
version = Mix.Project.config()[:version]

unless Regex.match?(~r/\Av(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\z/, tag) do
  Mix.raise("Release tag must be a stable semantic version prefixed with v")
end

unless tag == "v" <> version do
  Mix.raise("Release tag #{inspect(tag)} does not match project version #{inspect(version)}")
end

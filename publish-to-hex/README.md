# mbta/actions/publish-to-hex

Publishes an Elixir package **and documentation** with `mix hex.publish --yes`.
The runtime comes from the repository root's `.tool-versions`, with `~/.asdf`
cached using the same key as the library CI workflows. Mix dependencies and the
project are installed and compiled before validating and publishing.

The action requires a pushed tag whose commit is on `origin/main`, a complete
checkout of the triggering commit, and a stable `vMAJOR.MINOR.PATCH` tag exactly
matching `Mix.Project.config()[:version]`. Leading zeroes, prereleases, and build
metadata are rejected.

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `hex-api-key` | None | Hex.pm API key, required for publishing. |
| `validate-only` | `"false"` | Validate without installing, compiling, or publishing. |

`validate-only: "true"` expects the caller to have already installed the runtime,
installed dependencies, and compiled the project. It needs no Hex key and runs
the same release-context, ancestry, and version checks as publishing.

The API key is exposed as `HEX_API_KEY` only in the publishing step, not during
runtime setup, dependency installation, compilation, or validation. Do not set it
at workflow or job scope. Use the default Mix environment (`dev`) so documentation
dependencies such as `ex_doc` remain available.

## Caller workflow

Checkout is caller-owned. Use `fetch-depth: 0` and `persist-credentials: false`
in **both** the CI job that validates a release and the publishing job.
Keep triggers, read-only permissions, required CI jobs, environment protection,
runner selection, and concurrency in the caller: composite actions cannot
configure those safeguards.

For CI, replace the inline release check after compilation with:

```yaml
- name: Validate release tag
  if: >-
    github.event_name == 'push' && github.ref_type == 'tag' &&
    startsWith(github.ref_name, 'v')
  uses: mbta/actions/publish-to-hex@REVIEWED_ACTIONS_COMMIT_SHA
  with:
    validate-only: "true"
```

For publishing, retain the existing CI and security-analysis gates:

```yaml
on: [push, pull_request]

permissions:
  contents: read

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: ${{ github.ref_type != 'tag' }}

jobs:
  # ci and zizmor jobs omitted; ci includes validation above.
  publish:
    name: Publish to Hex.pm
    needs: [ci, zizmor]
    if: >-
      github.event_name == 'push' && github.ref_type == 'tag' &&
      startsWith(github.ref_name, 'v')
    runs-on: ubuntu-latest
    environment: hex-release
    concurrency:
      group: hex-publish
      cancel-in-progress: false
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
          fetch-depth: 0
      - uses: mbta/actions/publish-to-hex@REVIEWED_ACTIONS_COMMIT_SHA
        with:
          hex-api-key: ${{ secrets.HEX_API_KEY }}
```

`REVIEWED_ACTIONS_COMMIT_SHA` is deliberately a placeholder, not a released ref.
Replace it with the actual reviewed full commit SHA containing the shared action
in `mbta/actions`, and ensure that commit has been pushed before updating consumers.
Do not enable release publishing while the placeholder remains.
Configure the `hex-release` environment and a least-privilege Hex.pm API key
scoped to the package before releasing. Configure environment protection to require
approval and allow only intended release tags.

No action step creates a release tag or changes repository/environment settings.

## Development

Run `python3 publish-to-hex/test_publish_to_hex.py` from the repository root with
Elixir/Mix, Git, and ShellCheck installed. Install the test dependency with
`python3 -m pip install -r publish-to-hex/requirements-test.txt`.
The tests use temporary Git and Mix projects to exercise release checks, and
replace `mix` with a stub when testing the publishing command. They never publish
or require a Hex key. CI runs these tests separately from the publishing action.

## Testing

Run the tests using:

  ```sh
  mise exec shellcheck@0.11.0 -- python publish-to-hex/test_publish_to_hex.py
  ```

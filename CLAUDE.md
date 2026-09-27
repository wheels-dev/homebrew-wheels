# CLAUDE.md

## What This Is

Homebrew tap for the Wheels CLI. Installs the reviewed LuCLI runtime selected by wheels-dev/wheels `tools/lucli.json` as `wheels`.

## Formula Structure

- `Formula/wheels.rb` — the Homebrew formula
- Two version constants: `LUCLI_VERSION` and `MODULE_VERSION`
- Module resource block (commented out until first release with tarball asset)

## Development Commands

```bash
brew install --build-from-source Formula/wheels.rb  # test install
brew test wheels                                      # run tests
brew audit --strict Formula/wheels.rb                 # lint
```

## Auto-Update

`.github/workflows/auto-update.yml` reads the shared Wheels runtime pin and checks wheels-dev/wheels releases daily. It generates the formula URLs/checksums from that pin, rather than selecting the latest LuCLI release, then opens and auto-merges an update PR.

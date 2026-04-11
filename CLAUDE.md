# CLAUDE.md

## What This Is

Homebrew tap for the Wheels CLI. Installs LuCLI binary (from cybersonic/LuCLI releases) as `wheels`.

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

`.github/workflows/auto-update.yml` polls cybersonic/LuCLI and wheels-dev/wheels releases daily. If either has a new version, it updates the formula and auto-merges.

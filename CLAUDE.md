# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Homebrew tap that provides the `wheels` CLI command for macOS. The formula installs a wrapper script that delegates to LuCLI with the Wheels module.

## Key Files

- `Formula/wheels.rb` - Homebrew formula (dependencies, install, test)
- `README.md` - User-facing docs

## Architecture

The formula creates a bash wrapper at `$(brew --prefix)/bin/wheels` that:
1. Validates LuCLI is available in PATH
2. Checks the Wheels module is installed (auto-installs if missing)
3. Delegates to `lucli wheels` with all arguments passed through

LuCLI handles standard CLI argument conventions natively — no argument conversion needed.

## Dependencies

- LuCLI (`depends_on "lucli"`) — Lucee-native CLI
- Wheels module — installed via `post_install` hook and verified at runtime

## Development Commands

```bash
brew install --build-from-source ./Formula/wheels.rb
brew test wheels
brew audit --strict wheels
brew uninstall wheels
```

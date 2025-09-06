# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a Homebrew tap repository that provides the `wheels` CLI command for macOS. The repository contains a single Homebrew formula that creates a wrapper script for the CFWheels CommandBox CLI, allowing users to run `wheels` commands directly instead of prefixing with `box wheels`.

## Key Files

- `Formula/wheels.rb` - The main Homebrew formula that defines installation, dependencies, and the wrapper script
- `README.md` - User-facing documentation with installation and usage instructions

## Architecture

The formula creates a bash wrapper script at `/usr/local/bin/wheels` that:
1. Validates CommandBox is available in PATH
2. Checks that Wheels CLI tools are installed in CommandBox
3. Converts standard CLI argument formats (`--parameter=value`, `--flag`) to CommandBox format (`parameter=value`, `flag=true`)
4. Executes `box wheels` with the converted arguments

## Development Commands

This is a Homebrew formula repository, so standard Homebrew commands apply:

```bash
# Test the formula locally
brew install --build-from-source ./Formula/wheels.rb

# Test the formula
brew test wheels

# Audit the formula for style and correctness
brew audit --strict wheels

# Uninstall for testing
brew uninstall wheels
```

## Testing the Wrapper Script

The formula includes test logic in the `test do` block. The wrapper script handles:
- Parameter conversion from `--key=value` to `key=value`
- Boolean flag conversion from `--flag` to `flag=true` 
- Negated boolean flags from `--noFlag` to `flag=false`
- Standard argument passthrough

## Dependencies

- CommandBox (automatically installed via `depends_on "commandbox"`)
- Wheels CLI tools (installed via `box install wheels-cli` during formula installation)

## Formula Structure

The formula follows standard Homebrew conventions:
- Class name matches filename (`Wheels` < `wheels.rb`)
- Includes required metadata (desc, homepage, version)
- Uses `depends_on` for external dependencies
- Implements `install` method with installation logic
- Includes `test do` block for verification
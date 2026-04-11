# Homebrew Wheels

Homebrew formula for the [Wheels](https://wheels.dev) CLI — the command-line tool for the Wheels MVC framework.

## Install

```bash
brew tap wheels-dev/wheels
brew install wheels
```

## Usage

```bash
wheels new myapp            # scaffold a new project
wheels server start         # start development server
wheels test                 # run test suite
wheels generate model User  # generate a model
wheels --version            # show version info
```

## Requirements

- Java 21 (installed automatically as a dependency)
- macOS or Linux

## Update

```bash
brew upgrade wheels
```

## Uninstall

```bash
brew uninstall wheels
brew untap wheels-dev/wheels
```

## How It Works

This formula installs [LuCLI](https://github.com/cybersonic/LuCLI) (the Lucee CLI) as the `wheels` binary, along with the Wheels CLI module. LuCLI's binary-name detection automatically activates Wheels branding and routes commands to the Wheels module.

The formula auto-updates when new LuCLI or Wheels versions are released.

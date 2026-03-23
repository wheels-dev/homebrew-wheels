# Wheels Homebrew Tap

This tap provides the `wheels` command-line tool for macOS, powered by [LuCLI](https://github.com/cybersonic/LuCLI).

## What it does

The `wheels` command provides a full CLI for Wheels framework development — code generation, migrations, testing, dev servers, and more.

```bash
wheels new myapp
wheels generate model User name email
wheels dbmigrate latest
wheels test
```

## Installation

```bash
brew tap wheels-dev/wheels
brew install wheels
```

This automatically installs [LuCLI](https://github.com/cybersonic/LuCLI) as a dependency and the Wheels CLI module.

## Usage

```bash
# Create a new app
wheels new myapp

# Generate components
wheels generate model User
wheels generate controller Users
wheels generate scaffold Post title body:text

# Database
wheels dbmigrate latest

# Start dev server
wheels start

# Run tests
wheels test

# Get help
wheels --help
```

## Upgrading from v1 (CommandBox)

Version 2.0 replaces the CommandBox backend with LuCLI. The `wheels` command syntax is unchanged — existing workflows work as-is.

If you still need CommandBox, it continues to work independently (`box wheels ...`).

## Verification

```bash
which wheels
wheels --help
```

## Troubleshooting

1. **Command not found**: Ensure Homebrew's bin directory is in your PATH
2. **LuCLI not found**: Run `brew install lucli`
3. **Permission issues**: Try `brew uninstall wheels && brew install wheels`

## Updating

```bash
brew update
brew upgrade wheels
```

## Uninstalling

```bash
brew uninstall wheels
brew untap wheels-dev/wheels
```

## Contributing

Issues and pull requests welcome at [wheels-dev/homebrew-wheels](https://github.com/wheels-dev/homebrew-wheels).

## License

MIT License.

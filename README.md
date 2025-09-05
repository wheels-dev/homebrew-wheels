# CFWheels Homebrew Tap

This tap provides the `wheels` command-line tool for macOS, which serves as a convenient wrapper for the CFWheels CommandBox CLI.

## What it does

The `wheels` command allows you to run CFWheels CLI commands directly from your terminal without having to prefix them with `box`. 

Instead of typing:
```bash
box wheels generate model User
```

You can simply type:
```bash
wheels generate model User
```

## Installation

First, tap this repository:
```bash
brew tap wheels-dev/wheels
```

Then install the wheels CLI:
```bash
brew install wheels
```

### Prerequisites

This formula depends on CommandBox, which will be automatically installed if you don't already have it:
```bash
brew install commandbox
```

## Usage

Once installed, you can use the `wheels` command exactly like you would use `box wheels`:

```bash
# Generate a new model
wheels generate model User

# Run migrations
wheels migrate up

# Start a development server
wheels server start

# Get help
wheels --help
```

All arguments are passed through to the underlying `box wheels` command.

## Verification

To verify the installation worked correctly:

```bash
# Check that the command is available
which wheels

# Test the command (will show CFWheels CLI help)
wheels --help
```

## Troubleshooting

If you encounter issues:

1. **Command not found**: Make sure Homebrew's bin directory is in your PATH
2. **CommandBox not found**: Ensure CommandBox is installed: `brew install commandbox`
3. **Permission issues**: Try reinstalling: `brew uninstall wheels && brew install wheels`

## Updating

To update to the latest version:
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

Issues and pull requests are welcome at [https://github.com/wheels-dev/homebrew-wheels](https://github.com/wheels-dev/homebrew-wheels).

## License

This Homebrew formula is available as open source under the terms of the MIT License.
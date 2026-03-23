class Wheels < Formula
  desc "CLI for Wheels MVC framework (powered by LuCLI)"
  homepage "https://wheels.dev"
  url "file:///dev/null"
  sha256 "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  version "2.0.0"

  depends_on "lucli"

  def install
    # Create the wheels wrapper script
    (bin/"wheels").write <<~EOS
      #!/bin/bash
      # Wheels CLI wrapper — delegates to LuCLI
      #
      # LuCLI handles standard CLI argument conventions natively,
      # so no argument conversion is needed (unlike the old CommandBox wrapper).

      if ! command -v lucli &> /dev/null; then
        echo "Error: LuCLI is required but not found in PATH"
        echo "Please install LuCLI: brew install lucli"
        exit 1
      fi

      # Check if Wheels module is installed, install if needed
      if ! lucli modules list 2>/dev/null | grep -q "wheels"; then
        echo "Installing Wheels CLI module for LuCLI..."
        if ! lucli modules install wheels; then
          echo "Error: Failed to install Wheels CLI module"
          echo "Please try manually: lucli modules install wheels"
          exit 1
        fi
        echo "Wheels CLI module installed successfully"
      fi

      exec lucli wheels "$@"
    EOS

    chmod 0755, bin/"wheels"
  end

  def post_install
    # Pre-install the Wheels module so the first run is instant
    system "lucli", "modules", "install", "wheels"
  end

  test do
    assert_predicate bin/"wheels", :exist?
    assert_predicate bin/"wheels", :executable?

    # Verify the wrapper script references lucli
    assert_match "lucli", (bin/"wheels").read
  end
end

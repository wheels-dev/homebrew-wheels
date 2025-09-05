class Wheels < Formula
  desc "CLI wrapper for Wheels MVC framework"
  homepage "https://github.com/wheels-dev/homebrew-wheels"
  version "1.0.0"
  
  depends_on "commandbox"

  def install
    # Create the wheels wrapper script
    (bin/"wheels").write <<~EOS
      #!/bin/bash
      # Wheels CLI wrapper for CommandBox
      # Passes all arguments to 'box wheels'
      
      # Check if CommandBox is available
      if ! command -v box &> /dev/null; then
        echo "Error: CommandBox is required but not found in PATH"
        echo "Please install CommandBox: brew install commandbox"
        exit 1
      fi
      
      # Check if Wheels CLI tools are installed, install if needed
      if ! box help wheels &> /dev/null 2>&1; then
        echo "Installing Wheels CLI tools for CommandBox..."
        if ! box install wheels-cli; then
          echo "Error: Failed to install Wheels CLI tools"
          echo "Please try manually: box install wheels-cli"
          exit 1
        fi
        echo "Wheels CLI tools installed successfully"
      fi
      
      # Convert command line arguments from standard --parameter=value format
      # to CommandBox parameter=value format, and handle boolean flags
      converted_args=()
      for arg in "$@"; do
        if [[ "$arg" =~ ^--([^=]+)=(.*)$ ]]; then
          # Convert --parameter=value to parameter=value
          converted_args+=("${BASH_REMATCH[1]}=${BASH_REMATCH[2]}")
        elif [[ "$arg" =~ ^--no([A-Z].*)$ ]]; then
          # Convert --noFlag to flag=false
          flag_name=$(echo "${BASH_REMATCH[1]}" | sed 's/^./\L&/')
          converted_args+=("${flag_name}=false")
        elif [[ "$arg" =~ ^--([a-zA-Z].*)$ ]]; then
          # Convert --flag to flag=true
          converted_args+=("${BASH_REMATCH[1]}=true")
        else
          # Pass through other arguments unchanged
          converted_args+=("$arg")
        fi
      done
      
      # Pass converted arguments to box wheels
      exec box wheels "${converted_args[@]}"
    EOS
    
    # Make the script executable
    chmod 0755, bin/"wheels"
  end

  test do
    # Test that the command exists and has correct permissions
    assert_predicate bin/"wheels", :exist?
    assert_predicate bin/"wheels", :executable?
    
    # Test the help output (will fail gracefully if CommandBox isn't available)
    system "#{bin}/wheels", "--version" rescue nil
  end
end
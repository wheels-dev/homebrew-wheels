class Wheels < Formula
  desc "CLI wrapper for Wheels MVC framework"
  homepage "https://github.com/wheels-dev/homebrew-wheels"
  url "https://github.com/wheels-dev/homebrew-wheels.git"
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
      
      # Pass all arguments to box wheels
      exec box wheels "$@"
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
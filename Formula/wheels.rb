class Wheels < Formula
  desc "CLI for the Wheels MVC framework — powered by LuCLI"
  homepage "https://wheels.dev"
  license "Apache-2.0"

  LUCLI_VERSION = "0.3.7"
  MODULE_VERSION = ""

  if OS.mac?
    url "https://github.com/cybersonic/LuCLI/releases/download/v#{LUCLI_VERSION}/lucli-#{LUCLI_VERSION}-macos"
    sha256 "c9a122bbf5a0a8eeac9201e30f7928ddabd9c3c21da64dcfb75a6f790a8d0c36"
  elsif OS.linux?
    url "https://github.com/cybersonic/LuCLI/releases/download/v#{LUCLI_VERSION}/lucli-#{LUCLI_VERSION}-linux"
    sha256 "7a07b4d3f47eaea65022beb68cf7d0caf3060289815ded047d5d3b4d29e81441"
  end

  resource "wheels_module" do
    url "https://github.com/wheels-dev/wheels/releases/download/v#{MODULE_VERSION}/wheels-module-#{MODULE_VERSION}.tar.gz"
    sha256 "a19356621b3f361b6cf2b6da1bd3f8ca6d1774d87d3d35fd0c1d4a7a4f78b533"
  end

  depends_on "openjdk@21"

  def install
    binary = Dir["*"].first
    libexec.install binary => "wheels"
    chmod 0755, libexec/"wheels"

    resource("wheels_module").stage do
      (share/"wheels/module").install Dir["*"]
    end

    (share/"wheels").mkpath
    (share/"wheels/.module-version").write MODULE_VERSION

    (bin/"wheels").write <<~EOS
      #!/bin/bash
      BREW_PREFIX="#{HOMEBREW_PREFIX}/opt/wheels"
      WHEELS_MODULE_SRC="$BREW_PREFIX/share/wheels/module"
      WHEELS_MODULE_DST="$HOME/.wheels/modules/wheels"
      WHEELS_VERSION_SRC="$BREW_PREFIX/share/wheels/.module-version"
      WHEELS_VERSION_DST="$HOME/.wheels/modules/wheels/.module-version"

      if [ -f "$WHEELS_VERSION_SRC" ]; then
        src_ver=$(cat "$WHEELS_VERSION_SRC")
        dst_ver=""
        [ -f "$WHEELS_VERSION_DST" ] && dst_ver=$(cat "$WHEELS_VERSION_DST")
        if [ "$src_ver" != "$dst_ver" ]; then
          mkdir -p "$WHEELS_MODULE_DST"
          cp -R "$WHEELS_MODULE_SRC/"* "$WHEELS_MODULE_DST/"
          cp "$WHEELS_VERSION_SRC" "$WHEELS_VERSION_DST"
        fi
      fi

      export JAVA_HOME="#{Formula["openjdk@21"].opt_libexec}/openjdk.jdk/Contents/Home"
      exec "$BREW_PREFIX/libexec/wheels" "$@"
    EOS
    chmod 0755, bin/"wheels"
  end

  def caveats
    <<~EOS
      Java 21 is required and has been installed as a dependency.

      On first run, the Wheels module will be initialized in:
        ~/.wheels/modules/wheels/
    EOS
  end

  test do
    assert_predicate bin/"wheels", :executable?
    assert_predicate libexec/"wheels", :executable?
    assert_predicate share/"wheels/module/Module.cfc", :exist?
  end
end

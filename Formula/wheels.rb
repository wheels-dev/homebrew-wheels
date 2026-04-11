class Wheels < Formula
  desc "CLI for the Wheels MVC framework — powered by LuCLI"
  homepage "https://wheels.dev"
  license "Apache-2.0"

  LUCLI_VERSION = "0.3.3"
  MODULE_VERSION = "4.0.0+50"

  if OS.mac?
    url "https://github.com/cybersonic/LuCLI/releases/download/v#{LUCLI_VERSION}/lucli-#{LUCLI_VERSION}-macos"
    sha256 "6abf3fa8637ad66ef11592a91649a91b27c620cbaa7aaeb434725e1c15c6b676"
  elsif OS.linux?
    url "https://github.com/cybersonic/LuCLI/releases/download/v#{LUCLI_VERSION}/lucli-#{LUCLI_VERSION}-linux"
    sha256 "3c74ca291b8df26cc4c1e77c8162755b604acc03f6e0fa172602826d35a18126"
  end

  # Module tarball not yet available as release asset — placeholder until first
  # wheels release includes it. The auto-update workflow will fill in the real
  # SHA once the asset exists.
  #
  # resource "wheels_module" do
  #   url "https://github.com/wheels-dev/wheels/releases/download/v#{MODULE_VERSION}/wheels-module-#{MODULE_VERSION}.tar.gz"
  #   sha256 "PLACEHOLDER_MODULE_SHA"
  # end

  depends_on "openjdk@21"

  def install
    binary = Dir["*"].first
    libexec.install binary => "wheels"
    chmod 0755, libexec/"wheels"

    # Module resource will be staged here once available:
    # resource("wheels_module").stage do
    #   (share/"wheels/module").install Dir["*"]
    # end
    #
    # (share/"wheels").mkpath
    # (share/"wheels/.module-version").write MODULE_VERSION

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
  end
end

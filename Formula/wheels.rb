class Wheels < Formula
  desc "CLI for the Wheels MVC framework — powered by LuCLI"
  homepage "https://wheels.dev"
  license "Apache-2.0"

  LUCLI_VERSION = "0.3.7"
  MODULE_VERSION = "4.0.0-SNAPSHOT+1523"
  SQLITE_JDBC_VERSION = "3.49.1.0"

  if OS.mac?
    url "https://github.com/cybersonic/LuCLI/releases/download/v#{LUCLI_VERSION}/lucli-#{LUCLI_VERSION}-macos"
    sha256 "c9a122bbf5a0a8eeac9201e30f7928ddabd9c3c21da64dcfb75a6f790a8d0c36"
  elsif OS.linux?
    url "https://github.com/cybersonic/LuCLI/releases/download/v#{LUCLI_VERSION}/lucli-#{LUCLI_VERSION}-linux"
    sha256 "7a07b4d3f47eaea65022beb68cf7d0caf3060289815ded047d5d3b4d29e81441"
  end

  resource "wheels_module" do
    url "https://github.com/wheels-dev/wheels/releases/download/v#{MODULE_VERSION}/wheels-module-#{MODULE_VERSION}.tar.gz"
    sha256 "4aa7dc5e7dafa5b6bd521807c8c81ca7f9174e4e4840927f921bc89f34c20313"
  end

  resource "wheels_core" do
    url "https://github.com/wheels-dev/wheels/releases/download/v#{MODULE_VERSION}/wheels-core-#{MODULE_VERSION}.zip"
    sha256 "PLACEHOLDER_CORE_SHA"
  end

  # SQLite JDBC driver — shipped with the bottle so fresh installs can run the
  # default zero-config SQLite datasource on first `wheels start`. Without this,
  # Lucee 7's BundleProvider tries to fetch the OSGi bundle from update.lucee.org
  # at runtime and fails (the bundle is not on that update provider, and the
  # fallback S3 listing currently contains malformed entries that crash the
  # version parser). The wrapper copies this JAR into Lucee Express's lib/ext
  # on first invocation so the driver is on the classpath when migrations run.
  resource "sqlite_jdbc" do
    url "https://repo1.maven.org/maven2/org/xerial/sqlite-jdbc/#{SQLITE_JDBC_VERSION}/sqlite-jdbc-#{SQLITE_JDBC_VERSION}.jar"
    sha256 "5c8609d2ca341deb8c6f71778974b5ba4995c7d32d7c7c89d9392a3e72c39291"
  end

  depends_on "openjdk@21"

  def install
    binary = Dir["*"].first
    libexec.install binary => "wheels"
    chmod 0755, libexec/"wheels"

    resource("wheels_module").stage do
      (share/"wheels/module").install Dir["*"]
    end

    # Framework source (vendor/wheels/) is shipped as a companion zip. Extracting
    # it into share/wheels/framework/wheels/ matches the wheels-core zip's own
    # internal layout (top-level "wheels/" directory, verified against the
    # release workflow's smoke-test at tools/ci/smoke-test-module.sh).
    resource("wheels_core").stage do
      (share/"wheels/framework").install Dir["*"]
    end

    resource("sqlite_jdbc").stage do
      (share/"wheels/jdbc").install "sqlite-jdbc-#{SQLITE_JDBC_VERSION}.jar"
    end

    (share/"wheels").mkpath
    (share/"wheels/.module-version").write MODULE_VERSION

    java_home = if OS.mac?
      "#{Formula["openjdk@21"].opt_libexec}/openjdk.jdk/Contents/Home"
    else
      Formula["openjdk@21"].opt_libexec.to_s
    end

    (bin/"wheels").write <<~EOS
      #!/bin/bash
      BREW_PREFIX="#{HOMEBREW_PREFIX}/opt/wheels"
      WHEELS_MODULE_SRC="$BREW_PREFIX/share/wheels/module"
      WHEELS_MODULE_DST="$HOME/.wheels/modules/wheels"
      WHEELS_FRAMEWORK_SRC="$BREW_PREFIX/share/wheels/framework/wheels"
      WHEELS_FRAMEWORK_DST="$HOME/.wheels/modules/wheels/vendor/wheels"
      WHEELS_VERSION_SRC="$BREW_PREFIX/share/wheels/.module-version"
      WHEELS_VERSION_DST="$HOME/.wheels/modules/wheels/.module-version"
      WHEELS_JDBC_SRC="$BREW_PREFIX/share/wheels/jdbc"

      if [ -f "$WHEELS_VERSION_SRC" ]; then
        src_ver=$(cat "$WHEELS_VERSION_SRC")
        dst_ver=""
        [ -f "$WHEELS_VERSION_DST" ] && dst_ver=$(cat "$WHEELS_VERSION_DST")
        if [ "$src_ver" != "$dst_ver" ]; then
          mkdir -p "$WHEELS_MODULE_DST"
          cp -R "$WHEELS_MODULE_SRC/"* "$WHEELS_MODULE_DST/"
          if [ -d "$WHEELS_FRAMEWORK_SRC" ]; then
            mkdir -p "$WHEELS_FRAMEWORK_DST"
            cp -R "$WHEELS_FRAMEWORK_SRC/"* "$WHEELS_FRAMEWORK_DST/"
          fi
          cp "$WHEELS_VERSION_SRC" "$WHEELS_VERSION_DST"
        fi
      fi

      # Seed the SQLite JDBC driver into every Lucee Express install under
      # ~/.wheels/express/. Lucee 7's BundleProvider can't fetch this bundle
      # from update.lucee.org (the bundle isn't on that provider, and the
      # fallback S3 listing parser currently chokes on malformed entries).
      # Without it, the default zero-config SQLite datasource fails on first
      # use — `wheels migrate latest` exits 0 but no schema is created.
      # Idempotent: skipped per-express-version once the file is present.
      if [ -d "$WHEELS_JDBC_SRC" ] && [ -d "$HOME/.wheels/express" ]; then
        for express_dir in "$HOME/.wheels/express"/*/; do
          ext_dir="${express_dir}lib/ext"
          if [ -d "$ext_dir" ] && ! ls "$ext_dir"/sqlite-jdbc*.jar >/dev/null 2>&1; then
            cp "$WHEELS_JDBC_SRC"/sqlite-jdbc-*.jar "$ext_dir/" 2>/dev/null || true
          fi
        done
      fi

      export JAVA_HOME="#{java_home}"
      export LUCLI_HOME="$HOME/.wheels"
      exec "$BREW_PREFIX/libexec/wheels" "$@"
    EOS
    chmod 0755, bin/"wheels"
  end

  def caveats
    <<~EOS
      Java 21 is required and has been installed as a dependency.

      On first run, the Wheels module and framework source will be
      initialized in:
        ~/.wheels/modules/wheels/
        ~/.wheels/modules/wheels/vendor/wheels/

      The wrapper sets LUCLI_HOME=~/.wheels so all runtime state
      (modules, servers, deps, secrets) lives under that directory
      and stays isolated from any standalone LuCLI install.
    EOS
  end

  test do
    assert_predicate bin/"wheels", :executable?
    assert_predicate libexec/"wheels", :executable?
    assert_predicate share/"wheels/module/Module.cfc", :exist?
    assert_predicate share/"wheels/framework/wheels", :exist?
    assert_predicate share/"wheels/jdbc/sqlite-jdbc-#{SQLITE_JDBC_VERSION}.jar", :exist?
    assert_match(/\d+\.\d+\.\d+/, shell_output("#{bin}/wheels --version"))
  end
end

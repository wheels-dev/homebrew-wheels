class Wheels < Formula
  desc "CLI for the Wheels MVC framework — powered by LuCLI"
  homepage "https://wheels.dev"

  LUCLI_REPO = "wheels-dev/LuCLI"
  LUCLI_VERSION = "0.6.2.1"
  MODULE_VERSION = "4.1.2"
  SQLITE_JDBC_VERSION = "3.49.1.0"

  # Track the framework version, not the LuCLI wrapper version. The wheels
  # module ships independently of LuCLI and bumps far more often, so brew's
  # upgrade check must compare MODULE_VERSION — otherwise `brew upgrade` is
  # a silent no-op for module-only bumps (the common case).
  version MODULE_VERSION
  license "Apache-2.0"

  # on_macos / on_linux blocks, not a class-level `if OS.mac?`. Homebrew now
  # evaluates a formula once per bottle platform (golden_gate, tahoe, ...),
  # and a top-level conditional that leaves `url` undefined on the other
  # branch fails that pass with "invalid syntax in tap" — which made
  # `brew tap wheels-dev/wheels` refuse outright on current Homebrew.
  on_macos do
    url "https://github.com/#{LUCLI_REPO}/releases/download/v#{LUCLI_VERSION}/lucli-#{LUCLI_VERSION}-macos"
    sha256 "edcc131e2101c2e5ec08a235f6ac16e5bbdcd8e3f3ea167cb115704f515a0844"
  end
  on_linux do
    url "https://github.com/#{LUCLI_REPO}/releases/download/v#{LUCLI_VERSION}/lucli-#{LUCLI_VERSION}-linux"
    sha256 "edcc131e2101c2e5ec08a235f6ac16e5bbdcd8e3f3ea167cb115704f515a0844"
  end

  resource "wheels_module" do
    url "https://github.com/wheels-dev/wheels/releases/download/v#{MODULE_VERSION}/wheels-module-#{MODULE_VERSION}.tar.gz"
    sha256 "1b6c136a9e526fb89ebdef4e7b846a0dca50db0292aee0f4a523f02098c1753b"
  end

  resource "wheels_core" do
    url "https://github.com/wheels-dev/wheels/releases/download/v#{MODULE_VERSION}/wheels-core-#{MODULE_VERSION}.zip"
    sha256 "dac28f426c526a92fcb549cee3183e94b8faa34a887576a5943c79665e744d40"
  end

  # SQLite JDBC driver for the zero-config datasource emitted by `wheels new`.
  # Lucee 7's BundleProvider crashes when resolving sqlite-jdbc via the
  # bundleName hint, so wheels >=4.0 generates app.cfm without the hint and
  # relies on the JAR being on the classpath. The wrapper drops this JAR into
  # ~/.wheels/express/<lucee>/lib/ext/ on first run after LuCLI extracts.
  resource "sqlite_jdbc" do
    url "https://repo1.maven.org/maven2/org/xerial/sqlite-jdbc/#{SQLITE_JDBC_VERSION}/sqlite-jdbc-#{SQLITE_JDBC_VERSION}.jar"
    sha256 "5c8609d2ca341deb8c6f71778974b5ba4995c7d32d7c7c89d9392a3e72c39291"
  end

  depends_on "openjdk@21"

  # Mutually exclusive with the bleeding-edge wheels-be formula. Both expose
  # `bin/wheels`, so brew refuses to install both — user must explicitly switch:
  #   brew uninstall wheels && brew install wheels-be   # stable -> BE
  #   brew uninstall wheels-be && brew install wheels   # BE -> stable
  # brew's conflicts_with is symmetric — both formulas must declare the
  # conflict or `brew audit --strict` rejects the pair.
  conflicts_with "wheels-dev/wheels/wheels-be", because: "both wheels and wheels-be install the wheels CLI binary"

  def install
    binary = Dir["*"].first
    libexec.install binary => "wheels"
    chmod 0755, libexec/"wheels"

    resource("wheels_module").stage do
      (share/"wheels/module").install Dir["*"]
    end

    # Framework source (vendor/wheels/) is shipped as a companion zip whose
    # only top-level entry is a "wheels/" directory. Brew's resource.stage
    # auto-strips that wrapper before yielding, so re-introduce it explicitly
    # by installing into share/wheels/framework/wheels/ — that's the path the
    # wrapper syncs from.
    resource("wheels_core").stage do
      (share/"wheels/framework/wheels").install Dir["*"]
    end

    resource("sqlite_jdbc").stage do
      (share/"wheels/lib").install Dir["*.jar"]
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
      BREW_PREFIX="#{opt_prefix}"
      WHEELS_MODULE_SRC="$BREW_PREFIX/share/wheels/module"
      WHEELS_MODULE_DST="$HOME/.wheels/modules/wheels"
      WHEELS_FRAMEWORK_SRC="$BREW_PREFIX/share/wheels/framework/wheels"
      WHEELS_FRAMEWORK_DST="$HOME/.wheels/modules/wheels/vendor/wheels"
      WHEELS_VERSION_SRC="$BREW_PREFIX/share/wheels/.module-version"
      WHEELS_VERSION_DST="$HOME/.wheels/modules/wheels/.module-version"
      SQLITE_JDBC_SRC="$BREW_PREFIX/share/wheels/lib/sqlite-jdbc-#{SQLITE_JDBC_VERSION}.jar"

      # Intercept --version before LuCLI sees it: picocli treats it as its
      # own versionHelp flag and prints the runtime (LuCLI) version, not the
      # Wheels module version, and a bare `-v` never reaches version().
      # Help is NOT intercepted: `wheels --help`, `wheels help` and
      # `wheels <command> --help` all reach the module's showHelp(), whose
      # per-command help comes from Module.cfc itself, so it can't drift from
      # the commands (LuCLI forwards `<command> --help` as `showHelp <command>`).
      if [ "$#" -eq 1 ]; then
        case "$1" in
          --version|-v)
            # Prefer brew-installed version (SRC) over runtime cache (DST). SRC
            # always reflects what brew thinks is installed; DST may be stale
            # right after `brew install` / `brew upgrade` / channel switch
            # (the runtime cache syncs lazily on the next command).
            ver="unknown"
            [ -f "$WHEELS_VERSION_SRC" ] && ver=$(cat "$WHEELS_VERSION_SRC")
            [ "$ver" = "unknown" ] && [ -f "$WHEELS_VERSION_DST" ] && ver=$(cat "$WHEELS_VERSION_DST")
            echo "Wheels Version: $ver"
            echo ""
            echo ' __        ___               _     '
            echo ' \\ \\      / / |__   ___  ___| |___ '
            echo '  \\ \\ /\\ / /| '\\''_ \\ / _ \\/ _ \\ / __|'
            echo '   \\ V  V / | | | |  __/  __/ \\__ \\'
            echo '    \\_/\\_/  |_| |_|\\___|\\___|_|___/'
            echo ""
            echo "https://wheels.dev"
            exit 0
            ;;
        esac
      fi

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

      # Drop sqlite-jdbc into LuCLI's extracted Lucee lib/ext/ if missing. The
      # express dir only exists after first LuCLI run, so this is a no-op on
      # the very first invocation and self-heals on every run after.
      if [ -f "$SQLITE_JDBC_SRC" ]; then
        for ext_dir in "$HOME/.wheels/express"/*/lib/ext; do
          [ -d "$ext_dir" ] || continue
          [ -f "$ext_dir/sqlite-jdbc-#{SQLITE_JDBC_VERSION}.jar" ] && continue
          cp "$SQLITE_JDBC_SRC" "$ext_dir/" 2>/dev/null || true
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
    assert_predicate share/"wheels/lib/sqlite-jdbc-#{SQLITE_JDBC_VERSION}.jar", :exist?
    assert_match(/\d+\.\d+\.\d+/, shell_output("#{bin}/wheels --version"))
  end
end

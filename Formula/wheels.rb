class Wheels < Formula
  desc "CLI for the Wheels MVC framework — powered by LuCLI"
  homepage "https://wheels.dev"

  LUCLI_VERSION = "0.3.7"
  MODULE_VERSION = "4.0.0-SNAPSHOT+1630"
  SQLITE_JDBC_VERSION = "3.49.1.0"

  # Track the framework version, not the LuCLI wrapper version. The wheels
  # module ships independently of LuCLI and bumps far more often, so brew's
  # upgrade check must compare MODULE_VERSION — otherwise `brew upgrade` is
  # a silent no-op for module-only bumps (the common case).
  version MODULE_VERSION
  license "Apache-2.0"

  if OS.mac?
    url "https://github.com/cybersonic/LuCLI/releases/download/v#{LUCLI_VERSION}/lucli-#{LUCLI_VERSION}-macos"
    sha256 "c9a122bbf5a0a8eeac9201e30f7928ddabd9c3c21da64dcfb75a6f790a8d0c36"
  elsif OS.linux?
    url "https://github.com/cybersonic/LuCLI/releases/download/v#{LUCLI_VERSION}/lucli-#{LUCLI_VERSION}-linux"
    sha256 "7a07b4d3f47eaea65022beb68cf7d0caf3060289815ded047d5d3b4d29e81441"
  end

  resource "wheels_module" do
    url "https://github.com/wheels-dev/wheels/releases/download/v#{MODULE_VERSION}/wheels-module-#{MODULE_VERSION}.tar.gz"
    sha256 "772164825ad1787ec4fa9e50361b00914f96a7613cf68ef63ff7ec8e691cf424"
  end

  resource "wheels_core" do
    url "https://github.com/wheels-dev/wheels/releases/download/v#{MODULE_VERSION}/wheels-core-#{MODULE_VERSION}.zip"
    sha256 "149e27a44d269c23991279ece5d12f95fc3b7771a8e477b8956511ef6bf64a47"
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
      BREW_PREFIX="#{HOMEBREW_PREFIX}/opt/wheels"
      WHEELS_MODULE_SRC="$BREW_PREFIX/share/wheels/module"
      WHEELS_MODULE_DST="$HOME/.wheels/modules/wheels"
      WHEELS_FRAMEWORK_SRC="$BREW_PREFIX/share/wheels/framework/wheels"
      WHEELS_FRAMEWORK_DST="$HOME/.wheels/modules/wheels/vendor/wheels"
      WHEELS_VERSION_SRC="$BREW_PREFIX/share/wheels/.module-version"
      WHEELS_VERSION_DST="$HOME/.wheels/modules/wheels/.module-version"
      SQLITE_JDBC_SRC="$BREW_PREFIX/share/wheels/lib/sqlite-jdbc-#{SQLITE_JDBC_VERSION}.jar"

      # Intercept --version and --help before LuCLI sees them. picocli treats
      # these as `usageHelp`/`versionHelp` flags and short-circuits during arg
      # parsing — they would never reach our module's version()/showHelp() if
      # we exec'd LuCLI. Keep this block in sync with cli/lucli/Module.cfc's
      # version() and showHelp() — both paths must produce identical output.
      # Subcommand help (e.g. `wheels migrate --help`) is left to fall through;
      # LuCLI's preprocessModuleHelp rewrites it to module dispatch.
      if [ "$#" -eq 1 ]; then
        case "$1" in
          --version|-v)
            ver="unknown"
            [ -f "$WHEELS_VERSION_DST" ] && ver=$(cat "$WHEELS_VERSION_DST")
            [ "$ver" = "unknown" ] && [ -f "$WHEELS_VERSION_SRC" ] && ver=$(cat "$WHEELS_VERSION_SRC")
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
          --help|-h)
            ver="unknown"
            [ -f "$WHEELS_VERSION_DST" ] && ver=$(cat "$WHEELS_VERSION_DST")
            [ "$ver" = "unknown" ] && [ -f "$WHEELS_VERSION_SRC" ] && ver=$(cat "$WHEELS_VERSION_SRC")
            echo "Wheels CLI $ver"
            echo "  CFML MVC framework — code generation, migrations, testing, server management"
            echo ""
            echo "Usage:"
            echo "  wheels <command> [options]"
            echo ""
            echo "Getting Started:"
            echo "  new <name>          Scaffold a new Wheels application"
            echo "  start               Start the dev server"
            echo "  stop                Stop the dev server"
            echo "  reload              Reload the running app"
            echo ""
            echo "Code Generation:"
            echo "  generate            Generate model, controller, scaffold, migration, etc."
            echo "  destroy (or d)      Remove generated files"
            echo ""
            echo "Database:"
            echo "  migrate             Run database migrations (latest, up, down, info)"
            echo "  seed                Run database seeds"
            echo "  db                  Database management (reset, status, version)"
            echo ""
            echo "Testing & Inspection:"
            echo "  test                Run the test suite"
            echo "  browser             Browser-based tests (Playwright)"
            echo "  console             Open an interactive CFML REPL connected to your app"
            echo "  routes              Print the route table"
            echo "  info                Show framework version, environment, configuration"
            echo "  doctor              Diagnose project setup issues"
            echo "  validate            Validate project structure and configuration"
            echo "  analyze             Static analysis of project code"
            echo "  stats               Project statistics (lines of code, model counts, etc.)"
            echo "  notes               Find TODO / FIXME / HACK / OPTIMIZE comments"
            echo ""
            echo "Packages & Deployment:"
            echo "  packages            Install, update, search Wheels packages"
            echo "  upgrade             Upgrade the Wheels framework version in your project"
            echo "  deploy              Deploy your app (Kamal-compatible)"
            echo ""
            echo "Other:"
            echo "  mcp                 Configure Wheels MCP server for AI assistants"
            echo "  version             Show Wheels CLI version"
            echo "  help                Show this help"
            echo ""
            echo "For command-specific help: wheels <command> --help"
            echo ""
            echo "More info: https://guides.wheels.dev"
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

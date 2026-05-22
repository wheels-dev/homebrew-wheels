class WheelsBe < Formula
  desc "CLI for the Wheels MVC framework — bleeding-edge channel (develop snapshots)"
  homepage "https://wheels.dev"

  LUCLI_VERSION = "0.3.7"
  MODULE_VERSION = "4.0.2-snapshot.1938"
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
    url "https://github.com/wheels-dev/wheels-snapshots/releases/download/v#{MODULE_VERSION}/wheels-module-#{MODULE_VERSION}.tar.gz"
    sha256 "d70e2bca3ec14a8d4ddf46c941a24fdbc25a4bc661e7624714e255ab7a3e5ce3"
  end

  resource "wheels_core" do
    url "https://github.com/wheels-dev/wheels-snapshots/releases/download/v#{MODULE_VERSION}/wheels-core-#{MODULE_VERSION}.zip"
    sha256 "76c0765f6860bbb61d2e65e3ce8fdba3b80713496909f51855ae8c3d610a708f"
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

  # Mutually exclusive with the stable wheels formula. Both expose `bin/wheels`,
  # so brew refuses to install both — user must explicitly switch channels:
  #   brew uninstall wheels-be && brew install wheels   # BE -> stable
  #   brew uninstall wheels && brew install wheels-be   # stable -> BE
  conflicts_with "wheels-dev/wheels/wheels", because: "both wheels and wheels-be install the wheels CLI binary"

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

      # Intercept --version and --help before LuCLI sees them. picocli treats
      # these as `usageHelp`/`versionHelp` flags and short-circuits during arg
      # parsing — they would never reach our module's version()/showHelp() if
      # we exec'd LuCLI. Keep this block in sync with cli/lucli/Module.cfc's
      # version() and showHelp() — both paths must produce identical output.
      # Per-subcommand help (e.g. `wheels migrate --help`) is also intercepted
      # below — LuCLI's preprocessModuleHelp would otherwise drop the
      # subcommand name and route everything back to top-level help. See
      # wheels-dev/wheels#2313 (the F18 line on per-subcommand --help).
      if [ "$#" -eq 1 ]; then
        case "$1" in
          --version|-v)
            # Prefer brew-installed version (SRC) over runtime cache (DST). SRC
            # always reflects what brew thinks is installed; DST may be stale
            # right after `brew install` / `brew upgrade` / channel switch
            # (the runtime cache syncs lazily on the next non-help command).
            ver="unknown"
            [ -f "$WHEELS_VERSION_SRC" ] && ver=$(cat "$WHEELS_VERSION_SRC")
            [ "$ver" = "unknown" ] && [ -f "$WHEELS_VERSION_DST" ] && ver=$(cat "$WHEELS_VERSION_DST")
            echo "Wheels Version: $ver (bleeding-edge)"
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
            # Prefer brew-installed version (SRC) over runtime cache (DST). SRC
            # always reflects what brew thinks is installed; DST may be stale
            # right after `brew install` / `brew upgrade` / channel switch
            # (the runtime cache syncs lazily on the next non-help command).
            ver="unknown"
            [ -f "$WHEELS_VERSION_SRC" ] && ver=$(cat "$WHEELS_VERSION_SRC")
            [ "$ver" = "unknown" ] && [ -f "$WHEELS_VERSION_DST" ] && ver=$(cat "$WHEELS_VERSION_DST")
            echo "Wheels CLI $ver (bleeding-edge)"
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

      # Per-subcommand --help interception. LuCLI's preprocessModuleHelp
      # rewrites `wheels migrate --help` → `wheels --help`, dropping the
      # subcommand name before our module sees it, so each subcommand's help
      # has to be served from the wrapper. Skips JVM startup entirely, so
      # help is fast and consistent.
      sub_help_requested=0
      for arg in "$@"; do
        case "$arg" in
          --help|-h) sub_help_requested=1; break ;;
        esac
      done
      if [ "$sub_help_requested" = "1" ] && [ "$#" -ge 2 ]; then
        case "$1" in
          new)
            echo "Usage: wheels new <name> [options]"
            echo ""
            echo "Scaffold a new Wheels application in ./<name>."
            echo ""
            echo "Options:"
            echo "  --datasource=<name>    Default datasource name (default: wheels)"
            echo "  --template=<name>      Template to use (default: app)"
            echo ""
            echo "Examples:"
            echo "  wheels new myapp"
            echo "  wheels new blog --datasource=blogdb"
            exit 0
            ;;
          start)
            echo "Usage: wheels start [options]"
            echo ""
            echo "Start the Wheels development server for the current project."
            echo ""
            echo "Refuses to start from a directory that does not look like a"
            echo "Wheels project (no app/ + config/) to avoid creating phantom"
            echo "server registrations under ~/.wheels/servers/."
            exit 0
            ;;
          stop)
            echo "Usage: wheels stop [--name <name>] [--all]"
            echo ""
            echo "Stop the Wheels development server registered for the current"
            echo "directory. If no server is registered for cwd, lists all"
            echo "running servers and suggests --name."
            exit 0
            ;;
          reload)
            echo "Usage: wheels reload"
            echo ""
            echo "Reload the running app — clears caches, re-reads config,"
            echo "re-runs onApplicationStart. Equivalent to visiting"
            echo "/?reload=true&password=wheels in a browser."
            exit 0
            ;;
          generate|g)
            echo "Usage: wheels generate <type> <name> [attributes...]"
            echo ""
            echo "Generate Wheels components."
            echo ""
            echo "Types:"
            echo "  app           Create a new Wheels application (alias for 'wheels new')"
            echo "  model         Generate a model CFC"
            echo "  controller    Generate a controller CFC"
            echo "  view          Generate a view template"
            echo "  migration     Generate a database migration"
            echo "  scaffold      Generate model + controller + views + migration + tests + routes"
            echo "  api-resource  Generate API-only model + controller + migration + tests + routes"
            echo "  route         Add a resource route to config/routes.cfm"
            echo "  test          Generate a test spec file"
            echo "  property      Add a property to an existing model"
            echo "  helper        Generate a helper file"
            echo "  snippet       Insert a code snippet"
            echo ""
            echo "Examples:"
            echo "  wheels generate model User firstName:string lastName:string"
            echo "  wheels generate scaffold Post title:string body:text"
            echo "  wheels generate migration addEmailToUsers"
            exit 0
            ;;
          destroy|d)
            echo "Usage: wheels destroy <type> <name>"
            echo "       wheels destroy <name>          (type defaults to 'resource')"
            echo ""
            echo "Remove generated components. Requires --force to actually delete."
            echo ""
            echo "Types:"
            echo "  resource    Remove model + controller + views + tests + route + migration (default)"
            echo "  model       Remove model + test + generate drop-table migration"
            echo "  controller  Remove controller + test"
            echo "  view        Remove view directory (or single file with controller/view syntax)"
            echo ""
            echo "Examples:"
            echo "  wheels destroy User                   (remove the User resource)"
            echo "  wheels destroy controller Products    (remove just the Products controller)"
            echo "  wheels destroy model Product          (remove just the Product model)"
            echo "  wheels destroy view products/index    (remove a single view)"
            exit 0
            ;;
          migrate)
            echo "Usage: wheels migrate [latest|up|down|info]"
            echo ""
            echo "Run database migrations."
            echo ""
            echo "Actions:"
            echo "  latest   Apply all pending migrations (default)"
            echo "  up       Apply the next pending migration"
            echo "  down     Roll back the most recent migration"
            echo "  info     Show migration status (applied vs pending)"
            echo ""
            echo "Examples:"
            echo "  wheels migrate"
            echo "  wheels migrate latest"
            echo "  wheels migrate info"
            exit 0
            ;;
          seed)
            echo "Usage: wheels seed [--environment=<env>] [--mode=<auto|generate>] [--generate]"
            echo ""
            echo "Run database seed files. Reads app/db/seeds.cfm (shared) followed"
            echo "by app/db/seeds/<environment>.cfm (env-specific). Idempotent via"
            echo "seedOnce()."
            echo ""
            echo "Options:"
            echo "  --environment=<env>     Run env-specific seed file (default: auto-detect)"
            echo "  --mode=<auto|generate>  Mode (default: auto)"
            echo "  --generate              Use generated random data instead of seed files"
            echo ""
            echo "Examples:"
            echo "  wheels seed"
            echo "  wheels seed --environment=development"
            echo "  wheels seed --generate"
            exit 0
            ;;
          db)
            echo "Usage: wheels db <action> [options]"
            echo ""
            echo "Database management commands."
            echo ""
            echo "Actions:"
            echo "  reset    Drop all tables, run migrations, reseed (requires --force)"
            echo "  status   Show migration status (applied vs pending)"
            echo "  version  Show current schema version"
            echo ""
            echo "Examples:"
            echo "  wheels db status"
            echo "  wheels db status --pending"
            echo "  wheels db reset --force"
            exit 0
            ;;
          test)
            echo "Usage: wheels test [options]"
            echo ""
            echo "Run the WheelsTest BDD test suite."
            echo ""
            echo "Options:"
            echo "  --filter=<pattern>     Run only specs matching the pattern"
            echo "  --reporter=<format>    Reporter format: simple|json|tap (default: simple)"
            echo "  --directory=<path>     Run only specs in this directory (dotted path)"
            echo ""
            echo "Examples:"
            echo "  wheels test"
            echo "  wheels test --filter=UserSpec"
            echo "  wheels test --directory=tests.specs.models"
            exit 0
            ;;
          browser)
            echo "Usage: wheels browser <action>"
            echo ""
            echo "Browser-based testing (Playwright)."
            echo ""
            echo "Actions:"
            echo "  setup    Download Playwright JARs and Chromium browser (~370MB, one-time)"
            echo ""
            echo "Examples:"
            echo "  wheels browser setup"
            exit 0
            ;;
          console)
            echo "Usage: wheels console"
            echo ""
            echo "Open an interactive CFML REPL connected to your running app."
            echo "Server must be running (wheels start) first."
            exit 0
            ;;
          routes)
            echo "Usage: wheels routes [--filter=<pattern>] [--format=<text|json>]"
            echo ""
            echo "Print the application's route table."
            echo ""
            echo "Options:"
            echo "  --filter=<pattern>     Show only routes matching the pattern (name, path, controller)"
            echo "  --format=<text|json>   Output format (default: text)"
            echo ""
            echo "Examples:"
            echo "  wheels routes"
            echo "  wheels routes --filter=user"
            exit 0
            ;;
          info)
            echo "Usage: wheels info"
            echo ""
            echo "Show framework version, environment, and configuration details for"
            echo "the current app."
            exit 0
            ;;
          doctor)
            echo "Usage: wheels doctor [--verbose]"
            echo ""
            echo "Diagnose project setup issues. Reports problems with directory"
            echo "structure, missing config, mixin collisions, and other things"
            echo "that can crash a Wheels app."
            echo ""
            echo "Options:"
            echo "  --verbose    Show detailed diagnostic information"
            exit 0
            ;;
          validate)
            echo "Usage: wheels validate"
            echo ""
            echo "Validate project structure and configuration. Returns non-zero"
            echo "if issues are found."
            exit 0
            ;;
          analyze)
            echo "Usage: wheels analyze [--target=<all|models|controllers|views>] [--format=<text|json>]"
            echo ""
            echo "Static analysis of project code (anti-patterns, complexity"
            echo "metrics, cross-engine warnings)."
            echo ""
            echo "Options:"
            echo "  --target=<scope>     Scope (default: all)"
            echo "  --format=<format>    Output format (default: text)"
            exit 0
            ;;
          stats)
            echo "Usage: wheels stats [--format=<text|json>]"
            echo ""
            echo "Project statistics — lines of code, model counts, test coverage"
            echo "estimates."
            exit 0
            ;;
          notes)
            echo "Usage: wheels notes [--tags=<list>]"
            echo ""
            echo "Find TODO / FIXME / HACK / OPTIMIZE comments in your code."
            echo ""
            echo "Options:"
            echo "  --tags=<list>    Comma-separated tag list (default: TODO,FIXME,HACK,OPTIMIZE)"
            exit 0
            ;;
          packages)
            echo "Usage: wheels packages <action> [options]"
            echo ""
            echo "Install, update, search Wheels packages from the registry"
            echo "(default wheels-dev/wheels-packages)."
            echo ""
            echo "Actions:"
            echo "  list                                  List packages from the registry"
            echo "  search <query>                        Search by name/description/tag"
            echo "  show <name>                           Show details for a package"
            echo "  install <name>[@<version>]            Install (latest compat or pinned)"
            echo "  install <name> --force                Overwrite existing vendor/<name>"
            echo "  update <name> --yes                   Update a single package"
            echo "  update --all --yes                    Update all installed packages"
            echo "  remove <name>                         Delete vendor/<name>"
            echo "  registry refresh                      Bust the 24h registry cache"
            echo "  registry info                         Show registry URL and cache state"
            echo ""
            echo "Examples:"
            echo "  wheels packages list"
            echo "  wheels packages install wheels-sentry"
            echo "  wheels packages update --all --yes"
            exit 0
            ;;
          upgrade)
            echo "Usage: wheels upgrade [--to=<version>] [--dry-run]"
            echo ""
            echo "Upgrade the Wheels framework version in your project (vendor/wheels/)."
            echo ""
            echo "Options:"
            echo "  --to=<version>    Target version (default: latest stable)"
            echo "  --dry-run         Print what would change without applying"
            exit 0
            ;;
          deploy)
            echo "Usage: wheels deploy [verb] [options]"
            echo ""
            echo "Deploy your app to production via Kamal-compatible config"
            echo "(config/deploy.yml). Ported from Basecamp Kamal."
            echo ""
            echo "Verbs (selection):"
            echo "  init                 Scaffold config/deploy.yml + .kamal/secrets"
            echo "  setup                One-time server bootstrap + first deploy"
            echo "  (no verb)            Rolling deploy"
            echo "  rollback <ver>       Roll back to a previous version"
            echo "  config               Print resolved config as YAML"
            echo "  details              Aggregate app + proxy + accessory status"
            echo "  app|proxy|accessory  Container lifecycle"
            echo "  build|registry       Image build/push"
            echo "  prune|lock|secrets   Maintenance"
            echo ""
            echo "For full subcommand reference: wheels deploy docs"
            echo ""
            echo "Options:"
            echo "  --dry-run    Print commands without executing"
            exit 0
            ;;
          mcp)
            echo "Usage: wheels mcp [setup|wheels]"
            echo ""
            echo "Configure the Wheels MCP server for AI assistants."
            echo ""
            echo "Actions:"
            echo "  setup    Generate .mcp.json (Claude Code) and .opencode.json (OpenCode) in cwd"
            echo "  wheels   Run the stdio MCP server (used by AI IDEs, not invoked manually)"
            echo ""
            echo "Examples:"
            echo "  wheels mcp setup"
            exit 0
            ;;
          version)
            echo "Usage: wheels version"
            echo ""
            echo "Show the Wheels CLI version banner. Same as 'wheels --version'."
            exit 0
            ;;
          help)
            echo "Usage: wheels help"
            echo ""
            echo "Show top-level help. Same as 'wheels --help'."
            echo ""
            echo "For per-subcommand help: wheels <command> --help"
            exit 0
            ;;
          create)
            echo "Usage: wheels create <type> <name> [options]"
            echo ""
            echo "Create deployment scaffolding (config/deploy.yml, etc.)."
            echo ""
            echo "For details: wheels deploy init --help"
            exit 0
            ;;
          # Unknown subcommand — fall through to LuCLI which will report it.
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

class WheelsBe < Formula
  desc "CLI for the Wheels MVC framework — bleeding-edge channel (develop snapshots)"
  homepage "https://wheels.dev"

  LUCLI_REPO = "wheels-dev/LuCLI"
  LUCLI_VERSION = "0.6.2.3"
  MODULE_VERSION = "4.2.0-snapshot.3134"
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
    sha256 "418eebf3843caacacc3a405d51e32a157db8213c1ed1b87ef5b24ebf0148c6f4"
  end
  on_linux do
    url "https://github.com/#{LUCLI_REPO}/releases/download/v#{LUCLI_VERSION}/lucli-#{LUCLI_VERSION}-linux"
    sha256 "418eebf3843caacacc3a405d51e32a157db8213c1ed1b87ef5b24ebf0148c6f4"
  end

  resource "wheels_module" do
    url "https://github.com/wheels-dev/wheels-snapshots/releases/download/v#{MODULE_VERSION}/wheels-module-#{MODULE_VERSION}.tar.gz"
    sha256 "ebad382f90c26b65c90e3bc519bcac43011df2b7b824b29fb151a3dabe14a8ef"
  end

  resource "wheels_core" do
    url "https://github.com/wheels-dev/wheels-snapshots/releases/download/v#{MODULE_VERSION}/wheels-core-#{MODULE_VERSION}.zip"
    sha256 "da5f8f31b29e5ced8fc89d50c066457b14cf1bef71f478790aafa9fbeb7a2577"
  end

  # The offline documentation bundle: the prebuilt Astro/Starlight guides and
  # API reference, built to be served from /wheels-docs/. Staged into
  # share/wheels/docs and unpacked by the wrapper under ~/.wheels/docs/<version>/,
  # which is where the framework looks for it, so the guides and API reference
  # stay readable with no internet connection. Carries ONE docs version
  # (~32 MB); the full multi-version site is ~1.3 GB.
  resource "wheels_docs" do
    url "https://github.com/wheels-dev/wheels-snapshots/releases/download/v#{MODULE_VERSION}/wheels-docs-#{MODULE_VERSION}.zip"
    sha256 "68aaa7ddeac80bbdfcfecfedfd2bd845910106e166f3639898c0e9c5ead7fa6b"
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

    # Prebuilt docs bundle — unpacked by the wrapper on first run / upgrade.
    resource("wheels_docs").stage do
      (share/"wheels/docs").install Dir["*"]
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
      WHEELS_DOCS_SRC="$BREW_PREFIX/share/wheels/docs"
      WHEELS_DOCS_DST="$HOME/.wheels/docs/#{MODULE_VERSION}"

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
        esac
      fi

      if [ -f "$WHEELS_VERSION_SRC" ]; then
        src_ver=$(cat "$WHEELS_VERSION_SRC")
        dst_ver=""
        [ -f "$WHEELS_VERSION_DST" ] && dst_ver=$(cat "$WHEELS_VERSION_DST")
        if [ "$src_ver" != "$dst_ver" ]; then
          # Build the new module copy beside the installed one, then swap it in.
          # Copying over the installed copy (cp -R) kept files an older version
          # shipped and this one dropped, and `wheels new` copies them into every
          # new app (an old generator template in app/snippets/ overrides the
          # current one; old framework files land in vendor/wheels/). The version
          # marker is written into the new copy last, so a copy that fails part
          # way leaves the installed copy and its old marker alone, and the next
          # run tries again. The framework copy lives inside the module directory.
          wheels_module_new="$WHEELS_MODULE_DST.new.$$"
          wheels_framework_new="$wheels_module_new${WHEELS_FRAMEWORK_DST#"$WHEELS_MODULE_DST"}"
          rm -rf "$wheels_module_new"
          if mkdir -p "$wheels_module_new" \
            && cp -R "$WHEELS_MODULE_SRC/"* "$wheels_module_new/" \
            && { [ ! -d "$WHEELS_FRAMEWORK_SRC" ] \
              || { mkdir -p "$wheels_framework_new" && cp -R "$WHEELS_FRAMEWORK_SRC/"* "$wheels_framework_new/"; }; } \
            && cp "$WHEELS_VERSION_SRC" "$wheels_module_new/.module-version" \
            && rm -rf "$WHEELS_MODULE_DST" \
            && mv "$wheels_module_new" "$WHEELS_MODULE_DST"; then
            :
          else
            rm -rf "$wheels_module_new"
            echo "wheels: could not update $WHEELS_MODULE_DST; will retry on the next run" >&2
          fi
        fi
      fi

      # Local docs bundle. Version-gated like the module/framework sync above,
      # so `brew upgrade` refreshes the offline docs. The framework resolves this
      # directory from LUCLI_HOME + its own version.
      if [ -d "$WHEELS_DOCS_SRC" ] && [ ! -f "$WHEELS_DOCS_DST/manifest.json" ]; then
        echo "Installing offline docs for #{MODULE_VERSION}..." >&2
        rm -rf "$WHEELS_DOCS_DST"
        mkdir -p "$WHEELS_DOCS_DST"
        cp -R "$WHEELS_DOCS_SRC/"* "$WHEELS_DOCS_DST/" 2>/dev/null || true
      fi

      # --- docs-mirror begin ---------------------------------------------------
      # tests/wheels-be-docs-mirror.sh renders and runs this block.
      # Mirror the bundle into the current app's webroot when we are in one.
      # Required, not a convenience: the dev server's Lucee urlRewrite only
      # routes extension-less paths to the front controller, so the bundle's
      # extension-bearing asset URLs must be real files under the webroot for
      # the container to serve them.
      # Copied only when missing or when its manifest.json differs from the
      # cache's (a brew upgrade). A public/wheels-docs without manifest.json is
      # the user's own and is left alone; one with it is a docs mirror, whether
      # this wrapper, an older one or `wheels docs` made it. A plain copy, not
      # hardlinks, so edits in the app cannot change the shared cache; it is
      # built beside the target and renamed in. A failure warns and the command
      # still runs. The manifest is compared in bash rather than with cmp.
      # Same semantics as the Linux package launcher (wheels-dev/wheels#3821).
      WHEELS_DOCS_MIRROR="./public/wheels-docs"
      _wheels_docs_mirror() {
        local tmp="./public/.wheels-docs-new.$$" old="./public/.wheels-docs-old.$$"
        # Clear leftovers from runs that were killed mid-copy.
        rm -rf ./public/.wheels-docs-new.* ./public/.wheels-docs-old.*
        cp -R "$WHEELS_DOCS_DST" "$tmp" || { rm -rf "$tmp"; return 1; }
        if [ -e "$WHEELS_DOCS_MIRROR" ]; then
          mv "$WHEELS_DOCS_MIRROR" "$old" || { rm -rf "$tmp"; return 1; }
        fi
        mv "$tmp" "$WHEELS_DOCS_MIRROR" || { mv "$old" "$WHEELS_DOCS_MIRROR"; rm -rf "$tmp"; return 1; }
        rm -rf "$old"
      }
      if [ -f "./vendor/wheels/wheels.json" ] && [ -d "./public" ] && [ -f "$WHEELS_DOCS_DST/manifest.json" ]; then
        wheels_docs_manifest="$(cat "$WHEELS_DOCS_DST/manifest.json" 2>/dev/null)" || true
        if [ ! -e "$WHEELS_DOCS_MIRROR" ] || { [ -f "$WHEELS_DOCS_MIRROR/manifest.json" ] &&
            [ "$(cat "$WHEELS_DOCS_MIRROR/manifest.json" 2>/dev/null)" != "$wheels_docs_manifest" ]; }; then
          _wheels_docs_mirror 2>/dev/null ||
            echo "wheels: could not copy the offline docs into public/wheels-docs; continuing" >&2
        fi
      fi
      # --- docs-mirror end -----------------------------------------------------

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

      The prebuilt guides and API reference are installed offline under:
        ~/.wheels/docs/#{MODULE_VERSION}/

      and copied into an app's public/wheels-docs/ (when missing or out of
      date) when you run `wheels` from inside a project, so
      /wheels-docs/guides/ and /wheels-docs/api/ work with no internet
      connection.

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

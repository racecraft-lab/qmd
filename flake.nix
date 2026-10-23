{
  description = "QMD - Quick Markdown Search";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    {
      homeModules.default = { config, lib, pkgs, ... }:
        with lib;
        let
          cfg = config.programs.qmd;
        in
        {
          options.programs.qmd = {
            enable = mkEnableOption "QMD - on-device search engine for markdown notes";

            package = mkOption {
              type = types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
              defaultText = literalExpression "inputs.qmd.packages.\${pkgs.stdenv.hostPlatform.system}.default";
              description = "The qmd package to use.";
            };
          };

          config = mkIf cfg.enable {
            home.packages = [ cfg.package ];
          };
        };
    } //
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        packageJson = builtins.fromJSON (builtins.readFile ./package.json);
        version = packageJson.version;

        # Node 24.22.1 requires libuv 1.52.0 or later.
        nodeLibuv = pkgs.libuv.overrideAttrs (finalAttrs: _previousAttrs: {
          version = "1.52.1";
          src = pkgs.fetchFromGitHub {
            owner = "libuv";
            repo = "libuv";
            rev = "v${finalAttrs.version}";
            hash = "sha256-Y9Nph2LkT1qnOYTW3WCumWWwORnI4P7HxzBjUlGaL7M=";
          };
        });
        nodeUvwasi = pkgs.uvwasi.override { libuv = nodeLibuv; };
        nodeBrotli = pkgs.brotli.overrideAttrs (_finalAttrs: previousAttrs: {
          patches = previousAttrs.patches ++ [
            (pkgs.fetchurl {
              url = "https://github.com/google/brotli/commit/0ed4268a4401abcb4472096340477cf4af7d1a2b.patch";
              hash = "sha256-gzyh1x7thb3jwhxjpu4xATh3Qbiqi5qCJRNAlKZ3thk=";
            })
          ];
        });
        # Match the nghttp2 release bundled with Node 24.22.1.
        nodeNghttp2 = pkgs.nghttp2.overrideAttrs (finalAttrs: _previousAttrs: {
          version = "1.70.0";
          src = pkgs.fetchurl {
            url = "https://github.com/nghttp2/nghttp2/releases/download/v${finalAttrs.version}/nghttp2-${finalAttrs.version}.tar.bz2";
            hash = "sha256-j6yh94qpmsO8F2ina34PazbY5qYsE4GHUbHSBfAvlAU=";
          };
        });
        nghttp2RevertSink = {
          overrideAttrs = modifier:
            assert builtins.isAttrs modifier;
            assert builtins.attrNames modifier == [ "patches" ];
            assert builtins.isList modifier.patches;
            assert builtins.length modifier.patches == 1;
            let patch = builtins.head modifier.patches; in
            assert builtins.isAttrs patch;
            assert pkgs.lib.isDerivation patch;
            assert patch.outputHash == "sha256-RG87Qifjpl7HTP9ac2JwHj2XAbDlFgOpAnpZX3ET6gU=";
            assert (patch.outputHashAlgo or null) == null;
            assert patch.url == "https://github.com/nghttp2/nghttp2/commit/7784fa979d0bcf801a35f1afbb25fb048d815cd7.patch?full_index=1";
            assert patch.urls == [ "https://github.com/nghttp2/nghttp2/commit/7784fa979d0bcf801a35f1afbb25fb048d815cd7.patch?full_index=1" ];
            assert patch.drvPath == (pkgs.fetchpatch2 {
              url = "https://github.com/nghttp2/nghttp2/commit/7784fa979d0bcf801a35f1afbb25fb048d815cd7.patch?full_index=1";
              hash = "sha256-RG87Qifjpl7HTP9ac2JwHj2XAbDlFgOpAnpZX3ET6gU=";
              revert = true;
              excludes = [ "lib/includes/nghttp2/nghttp2.h" ];
            }).drvPath;
            assert pkgs.nghttp2.version == "1.67.1";
            assert (pkgs.nghttp2.patches or [ ]) == [ ];
            nodeNghttp2;
        };
        nodejs = (pkgs.nodejs.override (previousArgs: {
          callPackage = path: args: previousArgs.callPackage path (args // {
            brotli = nodeBrotli;
            libuv = nodeLibuv;
            uvwasi = nodeUvwasi;
          } // pkgs.lib.optionalAttrs
            (path == pkgs.path + "/pkgs/development/web/nodejs/nodejs.nix")
            { nghttp2 = nghttp2RevertSink; });
        })).overrideAttrs (finalAttrs: previousAttrs: {
          version = "24.22.1";
          # This emulator support is already included in Node 24.22.1.
          patches =
            let
              kept = pkgs.lib.remove
                (pkgs.path + "/pkgs/development/web/nodejs/configure-emulator.patch")
                previousAttrs.patches;
            in
            assert builtins.length kept + 1 == builtins.length previousAttrs.patches;
            kept;
          src = pkgs.fetchurl {
            url = "https://nodejs.org/dist/v${finalAttrs.version}/node-v${finalAttrs.version}.tar.xz";
            hash = "sha256-T1N5eWKAza6wwvNY/QS2oWzE+336g7WoyRqdljtDUjE=";
          };
        });
        nodeGyp = pkgs.node-gyp.override { inherit nodejs; };

        # Keep the locked package set; update only Bun and its verified release sources.
        bun = pkgs.bun.overrideAttrs (finalAttrs: previousAttrs: {
          version = "1.4.4";
          src = finalAttrs.passthru.sources.${system};
          passthru = previousAttrs.passthru // {
            sources = {
              "aarch64-darwin" = pkgs.fetchurl {
                url = "https://github.com/oven-sh/bun/releases/download/bun-v${finalAttrs.version}/bun-darwin-aarch64.zip";
                hash = "sha256-wkDX8My5DCY6hJ/NsJt+5iYw2SE0jtaq/ahrnVd7xRA=";
              };
              "aarch64-linux" = pkgs.fetchurl {
                url = "https://github.com/oven-sh/bun/releases/download/bun-v${finalAttrs.version}/bun-linux-aarch64.zip";
                hash = "sha256-uqa7NvUdblhWHgK76oJQOKnfRU9nPW13bou/hvjHhQ4=";
              };
              "x86_64-darwin" = pkgs.fetchurl {
                url = "https://github.com/oven-sh/bun/releases/download/bun-v${finalAttrs.version}/bun-darwin-x64-baseline.zip";
                hash = "sha256-1KFVrfv9CRVes7oFyeOlRPOSl9emhhbTx3WfZ6tcR9w=";
              };
              "x86_64-linux" = pkgs.fetchurl {
                url = "https://github.com/oven-sh/bun/releases/download/bun-v${finalAttrs.version}/bun-linux-x64.zip";
                hash = "sha256-v4zL+ysLgBWeD5ptFcVTF63YB3U028YTCj7bUvzLOVw=";
              };
            };
          };
        });

        # SQLite with loadable extension support for sqlite-vec
        sqliteWithExtensions = pkgs.sqlite.overrideAttrs (old: {
          configureFlags = (old.configureFlags or []) ++ [
            "--enable-load-extension"
          ];
        });

        nodeModulesHashes = {
          x86_64-linux = "sha256-jvq2TO0SxEV1BHyT6C32VQ916wMTM/D1nsV2rNcJQSo=";
          aarch64-darwin = "sha256-9vvR3KLmBc+4bfyWEyyM8FHWg+DfiDzUlwqUlm3NFc8=";

          # Populate these on first build for additional hosts if/when needed.
          aarch64-linux = pkgs.lib.fakeHash;
          x86_64-darwin = pkgs.lib.fakeHash;
        };

        nodeModules = pkgs.stdenvNoCC.mkDerivation {
          pname = "qmd-node-modules";
          inherit version;

          src = ./.;

          impureEnvVars = pkgs.lib.fetchers.proxyImpureEnvVars ++ [
            "GIT_PROXY_COMMAND"
            "SOCKS_SERVER"
          ];

          nativeBuildInputs = [
            bun
          ];

          dontConfigure = true;

          buildPhase = ''
            export HOME=$(mktemp -d)

            bun install \
              --backend copyfile \
              --frozen-lockfile \
              --ignore-scripts \
              --no-progress \
              --production
          '';

          installPhase = ''
            mkdir -p $out
            cp -R node_modules $out/
          '';

          dontFixup = true;

          outputHash = nodeModulesHashes.${system};
          outputHashAlgo = "sha256";
          outputHashMode = "recursive";
        };

        qmd = pkgs.stdenv.mkDerivation {
          pname = "qmd";
          inherit version;

          src = ./.;

          nativeBuildInputs = [
            bun
            pkgs.makeWrapper
            nodejs
            nodeGyp
            pkgs.python3  # needed by node-gyp to compile better-sqlite3
          ] ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
            pkgs.darwin.cctools  # provides libtool needed by node-gyp on macOS
          ];

          buildInputs = [ pkgs.sqlite ];

          buildPhase = ''
            export HOME=$(mktemp -d)

            cp -R ${nodeModules}/node_modules ./
            chmod -R u+w node_modules

            (cd node_modules/better-sqlite3 && node-gyp rebuild --release)
          '';

          installPhase = ''
            mkdir -p $out/lib/qmd
            mkdir -p $out/bin

            cp -r node_modules $out/lib/qmd/
            cp -r src $out/lib/qmd/
            cp -r skills $out/lib/qmd/
            cp package.json $out/lib/qmd/

            # The flake wraps `bun src/cli/qmd.ts` directly, so bin/qmd never
            # runs. Mirror its pre-import env here (#723): quiet llama/ggml
            # native logs for `qmd mcp` (stdio is JSON-RPC), and disable Metal
            # residency sets on Darwin so ggml's process-static destructor
            # does not dump a stack trace after a successful query
            # (ggml-org/llama.cpp#22593). `--run` fires before bun starts, so
            # the env is in place before the native binding loads. Preserve
            # explicit user values; QMD_METAL_KEEP_RESIDENCY=1 opts back in.
            makeWrapper ${bun}/bin/bun $out/bin/qmd \
              --add-flags "$out/lib/qmd/src/cli/qmd.ts" \
              --set DYLD_LIBRARY_PATH "${pkgs.sqlite.out}/lib" \
              --set LD_LIBRARY_PATH "${pkgs.sqlite.out}/lib${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ":${pkgs.stdenv.cc.libc.out}/lib:${pkgs.stdenv.cc.cc.lib}/lib"}" \
              --run 'if [ "$1" = mcp ]; then export LLAMA_LOG_LEVEL="''${LLAMA_LOG_LEVEL:-error}"; export GGML_LOG_LEVEL="''${GGML_LOG_LEVEL:-error}"; export GGML_BACKEND_SILENT="''${GGML_BACKEND_SILENT:-1}"; fi; if [ "$(uname -s)" = Darwin ] && [ "''${QMD_METAL_KEEP_RESIDENCY:-}" != 1 ]; then export GGML_METAL_NO_RESIDENCY="''${GGML_METAL_NO_RESIDENCY:-1}"; fi'
          '';

          meta = with pkgs.lib; {
            description = "On-device search engine for markdown notes, meeting transcripts, and knowledge bases";
            homepage = "https://github.com/tobi/qmd";
            license = licenses.mit;
            platforms = platforms.unix;
          };
        };
      in
      {
        packages = {
          default = qmd;
          qmd = qmd;
        };

        apps.default = {
          type = "app";
          program = "${qmd}/bin/qmd";
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            bun
            sqliteWithExtensions
          ];

          shellHook = ''
            export BREW_PREFIX="''${BREW_PREFIX:-${sqliteWithExtensions.out}}"
            echo "QMD development shell"
            echo "Run: bun src/cli/qmd.ts <command>"
          '';
        };
      }
    );

}

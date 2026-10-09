{
  description = "nixdash - NixOS config & monitoring, Rust engine + Qt/QML UIs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/7fc6f2c20af0";

    # Qt 6.11.2 cross-compiled for WebAssembly, plus the emsdk shim and a Rust
    # toolchain carrying wasm32-unknown-emscripten std. Only the wasm UI needs
    # it; the engine and desktop UI do not.
    qt6-wasm = {
      url = "path:/home/pde/Projects/qt6-wasm";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, qt6-wasm }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # cxx-qt interrogates a single qmake for headers, libs AND host tools
      # (moc, rcc, qmltyperegistrar, qmlcachegen). On NixOS those span separate
      # store paths, so it needs one merged prefix. qt6.env is what provides
      # it - a plain symlinkJoin does not, because nixpkgs' qmake has its
      # prefix baked in. See ~/docs/qt.md, Part 1.
      qtEnv = pkgs.qt6.env "nixdash-qt-env" (with pkgs.qt6; [
        qtdeclarative
        qtsvg
        qtshadertools
      ]);

      qtRuntime = {
        QT_PLUGIN_PATH = "${qtEnv}/${pkgs.qt6.qtbase.qtPluginPrefix}";
        QML2_IMPORT_PATH = "${qtEnv}/${pkgs.qt6.qtbase.qtQmlPrefix}";
      };
    in
    {
      packages.${system} = rec {
        # Single definition, shared with the home-manager module in
        # nix/hm-module.nix so the service and `nix build` cannot drift.
        engine = pkgs.callPackage ./nix/engine.nix { };

        # Shared with the home-manager module; see nix/ui.nix.
        ui = pkgs.callPackage ./nix/ui.nix { };

        default = engine;
      };

      devShells.${system} = {
        # Qt-for-wasm shell: `nix develop .#wasm`, then ui-wasm/build.sh
        wasm =
          let sdk = qt6-wasm.packages.${system}; in
          pkgs.mkShell {
            packages = [ sdk.rustToolchain ] ++ (with pkgs; [
              cmake ninja python3 git curl jq
            ]);

            EMSDK = sdk.emsdk;
            QT_HOST_PATH = sdk.hostQt;
            QT_WASM_TOOLCHAIN = "${sdk.qtbase-wasm}/lib/cmake/Qt6/qt.toolchain.cmake";

            # qt.toolchain.cmake RESETS CMAKE_PREFIX_PATH to qtbase's own
            # prefix, so -DCMAKE_PREFIX_PATH at the merged prefix is silently
            # dropped ("Could NOT find Qt6Qml"). This variable survives it.
            QT_ADDITIONAL_PACKAGES_PREFIX_PATH = sdk.qt6-wasm;

            # Must be the WASM qmake, never the host one.
            CXXQT_QMAKE = "${sdk.qt6-wasm}/bin/qmake";

            # rcc runs from the HOST Qt, which has zstd; the wasm Qt Core does
            # not, so a zstd-compressed .qrc fails to link with
            #   undefined symbol: qResourceFeatureZstd()
            # rcc only reaches for zstd once the payload is worth compressing,
            # so this stays hidden until a project has more than a file or two
            # of QML. Colon-separated; passed through to rcc.
            CXX_QT_AUTORCC_OPTIONS = "--no-zstd";

            shellHook = ''
              # emcc needs a writable cache. Copy from the REAL emscripten with
              # -L: the emsdk shim is a symlink farm into the store, and a copy
              # of it keeps read-only symlinks ("Could NOT find Threads").
              export EM_CACHE="$(mktemp -d)/emcache"
              cp -rL ${sdk.emscripten}/share/emscripten/cache "$EM_CACHE"
              chmod -R u+w "$EM_CACHE"
              export PATH="${sdk.emsdk}/share/emscripten:$PATH"
              echo "nixdash wasm UI  |  $(rustc --version)"
              echo "  ./ui-wasm/build.sh   then   ./ui-wasm/serve.sh"
            '';
          };

        default = pkgs.mkShell ({
        packages = with pkgs; [
          rustc
          cargo
          rustfmt
          clippy
          rust-analyzer
          qtEnv
          pkg-config
          curl
          jq
        ];

        # Qt6Gui/Qt6OpenGL .prl files reference -lGLX and -lOpenGL, which live
        # in libglvnd. buildInputs (not packages) so the cc wrapper picks up
        # its -L via NIX_LDFLAGS.
        buildInputs = [ pkgs.libglvnd ];

        QMAKE = "${qtEnv}/bin/qmake";
        RUST_LOG = "nixdash_engine=debug,tower_http=warn";

        # Qt logging does not reach stderr on this system, so a QML error
        # produces a running process, no window, and ZERO output. That has
        # cost hours. Make failures visible by default in the dev shell.
        QT_FORCE_STDERR_LOGGING = "1";
        } // qtRuntime);
      };

      # Importable from a channel-based Home Manager by path, so no flake
      # plumbing is needed on the consumer side:
      #   imports = [ /home/pde/Projects/nixdash/nix/hm-module.nix ];
      homeManagerModules.default = ./nix/hm-module.nix;

      apps.${system} = {
        default = {
          type = "app";
          program = "${self.packages.${system}.engine}/bin/nixdash-engine";
          meta.description = "nixdash engine";
        };
        ui = {
          type = "app";
          program = "${self.packages.${system}.ui}/bin/nixdash-ui";
          meta.description = "nixdash desktop UI";
        };
      };
    };
}

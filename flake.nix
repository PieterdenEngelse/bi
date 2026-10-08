{
  description = "b1 - Rust HTTP backend (axum)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/7fc6f2c20af0";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          rustc
          cargo
          rustfmt
          clippy
          rust-analyzer
          pkg-config
          curl   # for poking the API by hand
          jq
        ];
        RUST_LOG = "b1=debug,tower_http=debug";
      };

      packages.${system}.default = pkgs.rustPlatform.buildRustPackage {
        pname = "b1";
        version = "0.1.0";
        src = self;
        cargoLock.lockFile = ./Cargo.lock;
        nativeBuildInputs = [ pkgs.pkg-config ];
      };

      apps.${system}.default = {
        type = "app";
        program = "${self.packages.${system}.default}/bin/b1";
      };
    };
}

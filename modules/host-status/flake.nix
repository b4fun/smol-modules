{
  description = "host-status - Host monitoring daemon";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            bash
            jq
            curl
            netcat
            coreutils
            procps
            shellcheck
            remarshal  # provides toml2json
          ];

          shellHook = ''
            echo "host-status development environment"
            echo "Available commands:"
            echo "  ./bin/host-status --help"
            echo "  ./bin/host-status --once (test collection)"
            echo "  ./test/run_all.sh (run tests)"
            echo ""
            echo "Example config: host-status.example.toml"
          '';
        };
      }
    );
}

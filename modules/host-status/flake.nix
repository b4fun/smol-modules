{
  description = "host-status - Host status monitoring module";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in
        {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              go_1_21
              gopls
              gotools
              bc
              coreutils
            ];
            shellHook = ''
              echo "host-status dev shell"
              echo "Run 'go build' to build, or 'go run . -config examples/config.yaml' to test"
            '';
          };
        });

      packages = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in
        {
          default = pkgs.buildGoModule {
            pname = "host-status";
            version = "0.1.0";
            src = ./.;
            vendorHash = "sha256-wJPJlebGAGEHq6UEO16rkPW7CHldKDZjJZQpauVvTog=";
            
            buildInputs = [ pkgs.bc ];
            
            postInstall = ''
              mkdir -p $out/share/host-status/examples
              cp -r examples/* $out/share/host-status/examples/
              chmod +x $out/share/host-status/examples/providers/*.sh
            '';
            
            meta = with pkgs.lib; {
              description = "Host status monitoring with pull and push models";
              license = licenses.mit;
              platforms = supportedSystems;
            };
          };
        });
    };
}

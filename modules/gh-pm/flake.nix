{
  description = "gh-pm - GitHub Project Manager agent";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in
        {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [ bash gh jq curl coreutils toml2json ];
            shellHook = ''
              echo "gh-pm dev shell — run 'bash bin/gh-pm --help' to get started"
            '';
          };
        });

      packages = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in
        {
          default = pkgs.stdenv.mkDerivation {
            pname = "gh-pm";
            version = "0.0.1";
            src = ./.;
            nativeBuildInputs = [ pkgs.makeWrapper ];
            buildInputs = with pkgs; [ bash gh jq curl coreutils toml2json ];
            installPhase = ''
              mkdir -p $out/bin $out/share/gh-pm/lib
              cp bin/gh-pm $out/bin/gh-pm
              cp lib/*.sh  $out/share/gh-pm/lib/
              chmod +x $out/bin/gh-pm
              wrapProgram $out/bin/gh-pm \
                --set GH_PM_DIR $out/share/gh-pm \
                --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.bash pkgs.gh pkgs.jq pkgs.curl pkgs.coreutils pkgs.toml2json ]}
            '';
            meta = {
              description = "GitHub PM agent — polls for tasks, analyzes with LLM, dispatches workflows";
              license = pkgs.lib.licenses.mit;
              platforms = supportedSystems;
            };
          };
        });
    };
}

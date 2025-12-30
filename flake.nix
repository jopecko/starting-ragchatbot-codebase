{
  description = "Claude Code development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; # Or a specific branch/commit
    flake-utils.url = "github:numtide/flake-utils";
    claude-code.url = "github:sadjow/claude-code-nix";
  };

  outputs = { self, nixpkgs, flake-utils, claude-code, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [
              "claude-code"
            ];
          };
          overlays = [ claude-code.overlays.default ];
        };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.claude-code
          ];

          # Optional: Define actions to run when entering the shell
          shellHook = ''
            echo "Entering Claude Code development shell!"
            # Example: automatically install npm dependencies if node_modules is missing
            # if [ ! -d node_modules ]; then
            #   npm install
            # fi
          '';
        };
      });
}


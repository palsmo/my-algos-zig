# Author: palsmo

{
  description = ''
   ...
  '';

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOs/nixpkgs/nixos-unstable";
    zig.url = "github:mitchellh/zig-overlay";
    zls.url = "github:zigtools/zls/0.13.0";
  };

  outputs = { self, flake-utils, nixpkgs, zig, zls }: flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShell = pkgs.mkShell {
        buildInputs = [
          zig.packages.${system}.master
          zls.packages.${system}.default
        ];
      };
    }
  );
}

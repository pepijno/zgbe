{
  description = "zgbe";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.11";
    utils.url = github:numtide/flake-utils;
  };

  outputs = { self, nixpkgs, utils }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages."${system}";

        buildInputs = with pkgs; [
          gf
          zig
          zls
          xorg.libX11
          xorg.libXft
          xorg.libXcursor
          xorg.libXext
          xorg.libXfixes
          xorg.libXrandr
          xorg.libXinerama
          xorg.libXi
          libGL
        ];
      in
      rec {
        # `nix develop`
        devShell = pkgs.mkShell {
          inherit buildInputs;
        };
      });
}

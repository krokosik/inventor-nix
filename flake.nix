{
  description = "Experimental Autodesk Inventor 2026 on Nix, using locally supplied Windows files";

  inputs = {
    nix-overlayfs.url = "github:krokosik/nix-overlayfs/8ff690939b5946a631958361a9086df7879d73ce";
    nixpkgs.follows = "nix-overlayfs/nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-overlayfs,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ nix-overlayfs.overlays.default ];
      };
      wine = pkgs.callPackage ./packages/wine.nix { };
      wine-probe = pkgs.callPackage ./packages/wine-probe.nix { inherit wine; };
      importer = pkgs.writeShellApplication {
        name = "inventor-import";
        runtimeInputs = [ pkgs.python3 ];
        text = /* bash */ ''
          exec python3 ${./scripts/import-windows.py} "$@"
        '';
      };
      mkInventor = args: pkgs.callPackage ./packages/inventor.nix ({ inherit wine; } // args);
    in
    {
      packages.${system} = {
        inherit wine wine-probe importer;
        default = importer;
      };
      apps.${system}.default = {
        type = "app";
        program = "${importer}/bin/inventor-import";
        meta.description = "Import a local Windows Inventor installation";
      };
      lib.${system} = {
        inherit mkInventor;
        inherit (pkgs) requireFile;
      };
      overlays.default = nixpkgs.lib.composeManyExtensions [
        nix-overlayfs.overlays.default
        (final: _: {
          inventor-nix = {
            wine = final.callPackage ./packages/wine.nix { };
            mkInventor =
              args: final.callPackage ./packages/inventor.nix ({ wine = final.inventor-nix.wine; } // args);
          };
        })
      ];
      checks.${system} = {
        importer =
          pkgs.runCommand "inventor-importer-check"
            {
              nativeBuildInputs = [ pkgs.python3 ];
            }
            /* bash */ ''
              export PYTHONDONTWRITEBYTECODE=1
              python3 ${./checks/test-importer.py} ${./scripts/import-windows.py}
              touch "$out"
            '';
        oauth =
          pkgs.runCommand "inventor-oauth-check"
            {
              nativeBuildInputs = [
                pkgs.python3
                pkgs.bash
                pkgs.coreutils
              ];
            }
            /* bash */ ''
              python3 ${./checks/test-oauth.py} ${./scripts/oauth.sh}
              touch "$out"
            '';
      };
      formatter.${system} = pkgs.nixfmt-tree;
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.python3
          pkgs.nixfmt
          pkgs.shellcheck
          pkgs.hivex
        ];
      };
    };
}

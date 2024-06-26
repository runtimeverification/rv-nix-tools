{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/69493a13eaea0dc4682fd07e8a084f17813dbeeb";
  };

  description = "Pure Nix flake utility functions used in other RV repos";

  outputs = { self, nixpkgs }: 
  let
    mkSubdirectoryAppSrc = {
      pkgs,
      src,
      subdirectories,
      cleaner ? ({src} : src)
    } : pkgs.stdenv.mkDerivation {
      name = "subdirs-app-src";
      src = cleaner { inherit src; };

      dontBuild = true;

      patchPhase = pkgs.lib.strings.concatMapStringsSep " " (subdir: ''
        substituteInPlace pyproject.toml \
          --replace-fail ', subdirectory = "${subdir}"' ""
      '') subdirectories;

      installPhase = ''
        mkdir -p $out/
        cp -R * $out/
      '';
    };
  in
  {
    lib.mkSubdirectoryAppSrc = mkSubdirectoryAppSrc;

    lib.mkPykAppSrc = {
      pkgs,
      src,
      cleaner ? ({src} : src)
    } : mkSubdirectoryAppSrc {
      inherit pkgs src cleaner;
      subdirectories = [ "pyk" ];
    };

    lib.check-submodules = pkgs: dependencies:
      let
        hashes = with builtins;
          map (key: {
            name = key;
            rev = dependencies.${key}.rev;
          }) (attrNames dependencies);
      in pkgs.writeShellScriptBin "check-versions" ''
        STATUS=$(git submodule status --recursive);
        for elem in ${
          pkgs.lib.concatMapStringsSep " " ({ name, rev }: "${name},${rev}")
          hashes
        }; do
          IFS=","; set -- $elem;
          if ! grep -q "$2" <<< "$STATUS";
          then
              echo "$1 with hash '$2' does not match any current submodules:"
              echo "$STATUS"
              exit 1
          fi
        done
        echo "All dependencies match"
      '';
    lib.update-from-submodules = pkgs: lockFile: dependencies:
      let
        lock = (builtins.fromJSON (builtins.readFile lockFile)).nodes;
        deps = with builtins;
          map (key: {
            name = key;
            var = builtins.replaceStrings [ "-" "_" ] [ "" "" ]
              (pkgs.lib.toUpper key);
            submodule = dependencies.${key}.submodule;
            owner = lock.${key}.original.owner;
            repo = lock.${key}.original.repo;
          }) (attrNames dependencies);
      in pkgs.writeShellScriptBin "check-versions" ''
        STATUS=$(git submodule status --recursive);
        ${pkgs.lib.concatMapStringsSep "\n"
        ({ name, var, owner, repo, submodule }:
          "${var}=$(echo \"$STATUS\" | ${pkgs.gawk}/bin/awk '$2 == \"${submodule}\" {gsub(/[\\+,-]/, \"\"); print $1}')\n" +
          "echo \"Setting ${name} to 'github:${owner}/${repo}/\${${var}}'\""
        ) deps}

        nix flake lock \
        ${
          pkgs.lib.concatMapStringsSep " \\\n"
          ({ name, var, owner, repo, ... }:
            "  --override-input ${name} github:${owner}/${repo}/\$${var}") deps
        } \
          --recreate-lock-file 
      '';
  };
}

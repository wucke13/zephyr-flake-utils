{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";
    flake-utils.url = "github:numtide/flake-utils";
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, ... }@inputs:
    flake-utils.lib.eachSystem [
      "x86_64-linux"
      "x86_64-darwin"
      "aarch64-linux"
      "aarch64-darwin"

      # not supported by mach-nix
      # "x86_64-windows"
    ]
      (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [
              inputs.devshell.overlays.default
              (final: prev: {
                npmlock2nix = import inputs.npmlock2nix { pkgs = prev; };
              })
            ];
          };

          # parse a filename string from a zephyr sdk release asset
          # returns the following attribute set:
          # { type, hostArch, targetArch }
          parse = x:
            let
              types = [ "hosttools" "toolchain" "zephyr-sdk" ];
              host-os = [ "darwin" "linux" "windows" ];
              host-arch = [ "aarch64" "x86_64" ];
              target-arch = [
                "aarch64"
                "arc"
                "arc64"
                "arm"
                "microblazeel"
                "mips"
                "nios2"
                "riscv64"
                "sparc"
                "x86_64"
                "xtensa-espressif_esp32"
                "xtensa-espressif_esp32s2"
                "xtensa-espressif_esp32s3"
                "xtensa-intel_ace15_mtpm"
                "xtensa-intel_apl_adsp"
                "xtensa-intel_bdw_adsp"
                "xtensa-intel_byt_adsp"
                "xtensa-intel_s1000"
                "xtensa-intel_tgl_adsp"
                "xtensa-nxp_imx8m_adsp"
                "xtensa-nxp_imx_adsp"
                "xtensa-sample_controller"
              ];
              regexVariants = x: "(" + (builtins.concatStringsSep "|" x) + ")";
              regex = "${regexVariants types}(-[0-9.]+)?_${regexVariants host-os}-${regexVariants host-arch}(_${regexVariants target-arch}[-_]([^.]*))?\.(.*)$";
              xWithCorrectOsNames = builtins.replaceStrings [ "macos" ] [ "darwin" ] x;
              matches = builtins.match regex xWithCorrectOsNames;
            in
            rec {
              type = builtins.elemAt matches 0;
              hostArch = "${builtins.elemAt matches 3}-${builtins.elemAt matches 2}";
              targetArch = builtins.elemAt matches 5;
            };

          # build a zephyr related derivation
          zephyrBuilder = { name, url, sha256, version, ... }: with pkgs; stdenv.mkDerivation {
            inherit name version;
            src = fetchurl {
              inherit url sha256;
            };

            nativeBuildInputs = [ autoPatchelfHook ];
            buildInputs = [ stdenv.cc.cc.lib self.packages.${system}.zephyr-python ];

            installPhase = ''
              runHook preInstall
              mkdir $out
              cp --recursive * $out/
              cd $out/
              runHook postInstall
            '';
          };
        in
        rec {
          packages = {
            # a python with all zephyr packages installed
            zephyr-python = pkgs.python38.withPackages (ps: with ps; [
              west

              # taken from https://github.com/zephyrproject-rtos/zephyr/tree/main/scripts
              # out of requirements-*.txt on 2023-09-21

              ### base ###
              pyelftools
              pyyaml
              pykwalify
              canopen
              packaging
              progress
              psutil
              pylink-square
              pyserial
              requests
              anytree
              intelhex

              ### build-test ###
              colorama
              ply
              gcovr
              coverage
              pytest
              mypy
              mock

              ### compliance ###
              python-magic
              lxml
              junitparser
              pylint
              yamllint

              ### extras ###
              anytree
              # junit2html
              # clang-format
              # lpc_checksum
              pillow
              # imgtool
              grpcio-tools
              protobuf
              pygithub
              graphviz
              # zcbor

              ### run-test ###
              pyocd
              tabulate
              natsort
              cbor
              psutil
            ]);
          } // (
            let
              lib = pkgs.lib;
              inherit (builtins)
                filter
                foldl'
                fromJSON
                listToAttrs
                map
                readDir
                readFile
                replaceStrings;
              inherit (pkgs.lib)
                filterAttrs
                flatten
                mapAttrsToList
                optionalString
                removePrefix
                removeSuffix;
              removeFileExt = str: foldl' (acc: ext: removeSuffix ".${ext}" acc) str [ "7z" "tar.gz" "tar.xz" ];
              fileNameToVersion = name: removePrefix "v" (removeSuffix ".json" name);
              dirEntries = readDir ./zephyr-assets;
              assetFiles = filterAttrs (n: v: v == "regular") dirEntries;
              assetFilesList = mapAttrsToList
                (name: value: {
                  version = fileNameToVersion name;
                  assets = filter (x: system == x.meta.hostArch) (map
                    (x: x // {
                      meta = parse x.name;
                    })
                    (fromJSON (readFile (./zephyr-assets + "/${name}"))));
                })
                assetFiles;
              packagesList = flatten (map
                (release: map
                  (file:
                    let meta = file.meta; in
                    {
                      name = "${meta.type}${optionalString (meta.targetArch != null) "-${meta.targetArch}" }-${replaceStrings [ "." ] [ "_" ] release.version}";
                      value = zephyrBuilder (file // { inherit (release) version; });
                    })
                  release.assets)
                assetFilesList);
            in
            listToAttrs packagesList
          );

          devShell =
            let
              sdk = packages.zephyr-sdk-0_16_1_linux-x86_64-0_16_1;
              toolchain = packages.toolchain_linux-x86_64_arm-zephyr-eabi-0_16_1;
            in
            pkgs.mkShell {
              ZEPHYR_TOOLCHAIN_VARIANT = "zephyr";
              ZEPHYR_SDK_INSTALL_DIR = sdk;
              nativeBuildInputs = with pkgs; [
                sdk
                toolchain
                packages.zephyr-python
                cmake
                ninja
                dtc
              ];
            };
        }
      );
}

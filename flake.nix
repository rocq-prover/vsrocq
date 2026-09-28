{
  description = "VsRocq, a language server for Rocq based on LSP";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # Keep this revision in sync with PIN_COQ in the CI workflow.
    rocq-master.url = "github:rocq-prover/rocq/5358976838128ff6125ee64e3b3d08dac45fc2f3";
    rocq-master.inputs.nixpkgs.follows = "nixpkgs-unstable";
    rocq-master.inputs.flake-utils.follows = "flake-utils";
  };

  outputs = {
    self,
    nixpkgs-unstable,
    flake-utils,
    rocq-master,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      lib = nixpkgs-unstable.lib;
      pkgs = nixpkgs-unstable.legacyPackages.${system};
      version = "2.5.0";
      defaultTarget = "8-20";
      client = {
        name = "vsrocq-client";
        vscodeExtPublisher = "rocq-prover";
        vscodeExtName = "vsrocq";
        vscodeExtUniqueId = "rocq-prover.vsrocq";
      };
      coqTarget = coq: {
        inherit coq;
        ocamlPackages = coq.ocamlPackages;
      };
      wrapperShellHook = ''
        export PATH="$PWD/language-server/.wrappers:$PATH"
      '';
      memprofLimitsOverride = {
        version = "0.3.0";
        src = pkgs.fetchFromGitLab {
          owner = "gadmm";
          repo = "memprof-limits";
          rev = "v0.3.0";
          hash = "sha256-k/uB1jDQtE/PkVPU8zg8cpOmlPttTWVpKerQ0HuWfuI=";
        };
      };
      rocq = pkgs.rocq-core.override {
        version = rocq-master.outPath;
        customOCamlPackages = pkgs.ocaml-ng.ocamlPackages_4_14;
      };

      targets = {
        "8-18" =
          coqTarget pkgs.coq_8_18
          // {
            package = "vsrocq-language-server-coq-8-18";
            yojsonVersion = "2.2.2";
            shellExtraInputs = [pkgs.ocamlPackages.ocaml-lsp];
          };
        "8-19" =
          coqTarget pkgs.coq_8_19
          // {
            package = "vsrocq-language-server-coq-8-19";
            yojsonVersion = "2.2.2";
          };
        "8-20" =
          coqTarget pkgs.coq_8_20
          // {
            package = "vsrocq-language-server-coq-8-20";
            yojsonVersion = "2.2.2";
          };
        "9" =
          coqTarget pkgs.coq_9_0
          // {
            package = "vsrocq-language-server-rocq-9";
            yojsonVersion = "2.2.2";
            shellHook = wrapperShellHook;
          };
        "9-1" =
          coqTarget pkgs.coq_9_1
          // {
            package = "vsrocq-language-server-rocq-9-1";
            yojsonVersion = "2.2.2";
            memprofLimits = memprofLimitsOverride;
            shellHook = wrapperShellHook;
          };
        "9-2" =
          coqTarget pkgs.coq_9_2
          // {
            package = "vsrocq-language-server-rocq-9-2";
            memprofLimits = memprofLimitsOverride;
            shellHook = wrapperShellHook;
          };
        "9-3" =
          coqTarget pkgs.coq_9_3
          // {
            package = "vsrocq-language-server-rocq-9-3";
            memprofLimits = memprofLimitsOverride;
            shellHook = wrapperShellHook;
          };
        master =
          coqTarget rocq
          // {
            package = "vsrocq-language-server-coq-master";
            yojsonVersion = "2.2.2";
            memprofLimits = memprofLimitsOverride;
          };
      };

      mkOcamlPackages = target:
        if !(target ? yojsonVersion) && !(target ? memprofLimits)
        then target.ocamlPackages
        else
          target.ocamlPackages.overrideScope (_: super: {
            yojson =
              if target ? yojsonVersion
              then
                super.yojson.overrideAttrs (_: {
                  version = target.yojsonVersion;
                  __intentionallyOverridingVersion = true;
                })
              else super.yojson;
            "memprof-limits" =
              if target ? memprofLimits
              then
                super."memprof-limits".overrideAttrs (old: {
                  version = target.memprofLimits.version;
                  src = target.memprofLimits.src;
                  nativeBuildInputs = (old.nativeBuildInputs or []) ++ [super.cppo];
                  meta = old.meta // {broken = false;};
                })
              else super."memprof-limits";
          });

      languageServerDependencies = [
        "ocaml"
        "findlib"
        "yojson"
        "ppx_inline_test"
        "ppx_blob"
        "ppx_assert"
        "ppx_sexp_conv"
        "ppx_deriving"
        "ppx_optcomp"
        "ppx_import"
        "sexplib"
        "ppx_yojson_conv"
        "lsp"
        "sel"
        "memprof-limits"
      ];
      mkLanguageServer = target: let
        ocamlPackages = mkOcamlPackages target;
      in
        ocamlPackages.buildDunePackage {
          duneVersion = "3";
          pname = "vsrocq-language-server";
          inherit version;
          src = ./language-server;
          nativeBuildInputs = [target.coq];
          buildInputs =
            [
              target.coq
              pkgs.dune_3
            ]
            ++ map (name: ocamlPackages.${name}) languageServerDependencies;
          propagatedBuildInputs = [ocamlPackages.zarith];
          preBuild = ''
            make dune-files
          '';
        };
    in let
      mkClient = let
        yarnDeps = name: path:
          pkgs.mkYarnModules {
            pname = "${name}_yarn_deps";
            inherit version;
            packageJSON = ./${path}/package.json;
            yarnLock = ./${path}/yarn.lock;
            yarnNix = ./${path}/yarn.nix;
          };
        clientDeps = yarnDeps "client" "client";
        goalViewUiDeps = yarnDeps "goal_ui" "client/goal-view-ui";
        searchUiDeps = yarnDeps "search_ui" "client/search-ui";
        linkDeps = dependencies: path: ''
          ln -s ${dependencies}/node_modules ${path}
          export PATH=${dependencies}/node_modules/.bin:$PATH
        '';
        links = [
          (linkDeps clientDeps ".")
          (linkDeps goalViewUiDeps "./goal-view-ui")
          (linkDeps searchUiDeps "./search-ui")
        ];
        commands = builtins.concatStringsSep "\n" links;
        nativeBuildInputs = [
          pkgs.nodejs
          pkgs.yarn
          clientDeps
          goalViewUiDeps
          searchUiDeps
        ];
        extension = pkgs.vscode-utils.buildVscodeExtension {
          inherit (client) name vscodeExtName vscodeExtPublisher vscodeExtUniqueId;
          inherit version;
          src = ./client;
          inherit nativeBuildInputs;
          installPrefix = "share/vscode/extensions/${client.vscodeExtUniqueId}";
          buildPhase =
            commands
            + ''
              cd goal-view-ui
              yarn run build
              cd ../search-ui
              yarn run build
              cd ..
              webpack --mode=production --devtool hidden-source-map
            '';
        };
      in {
        inherit extension;
        vsix_archive = pkgs.stdenv.mkDerivation {
          name = "vsrocq-client-vsix";
          unpackPhase = ''
            cp -r ${extension}/share/vscode/extensions/${client.vscodeExtUniqueId}/* .
            ls -alt
            pwd
          '';
          nativeBuildInputs = [
            extension
            clientDeps
            pkgs.nodejs
            pkgs.yarn
          ];
          buildPhase = ''
            export PATH=${clientDeps}/node_modules/.bin:$PATH
            bash -c "yes y | vsce package"
            mkdir -p $out/share/vscode/extensions
            cp *.vsix $out/share/vscode/extensions
          '';
        };
      };

      clientPackage = mkClient;
      targetPackages =
        lib.mapAttrs' (_: target: {
          name = target.package;
          value = mkLanguageServer target;
        })
        targets;
      targetShells = lib.mapAttrs (_: target:
        pkgs.mkShell {
          buildInputs =
            clientPackage.extension.buildInputs
            ++ targetPackages.${target.package}.buildInputs
            ++ (target.shellExtraInputs or [])
            ++ [pkgs.git];
          shellHook = target.shellHook or "";
        })
      targets;
    in {
      formatter = pkgs.alejandra;
      packages =
        targetPackages
        // {
          default = targetPackages.${targets.${defaultTarget}.package};
          vsrocq-client = clientPackage;
        };
      devShells =
        lib.mapAttrs' (targetName: _: {
          name = "vsrocq-${targetName}";
          value = targetShells.${targetName};
        })
        targets
        // {
          default = targetShells.${defaultTarget};
        };
    });
}

{
  description = "VsRocq, a language server for Rocq based on LSP";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    rocq-master = { url = "github:rocq-prover/rocq/aeabefe987b1a9aa6bfcaa1ed44b4dcb9124c1d6"; }; # Should be kept in sync with PIN_COQ in CI workflow
    rocq-master.inputs.nixpkgs.follows = "nixpkgs";

  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    rocq-master,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      name = "vsrocq-client";
      vscodeExtPublisher = "rocq-prover";
      vscodeExtName = "vsrocq";
      vscodeExtUniqueId = "rocq-prover.vsrocq";
      vsrocq_version = "2.3.1";
      rocq = rocq-master.packages.${system};
    in rec {
      formatter = nixpkgs.legacyPackages.${system}.alejandra;

      packages = {
        default = self.packages.${system}.vsrocq-language-server-coq-8-20;

        vsrocq-language-server-coq-8-18 =
          # Notice the reference to nixpkgs here.
          with import nixpkgs {inherit system;}; let
            ocamlPackages = ocaml-ng.ocamlPackages_4_14;
          in
            ocamlPackages.buildDunePackage {
              duneVersion = "3";
              pname = "vsrocq-language-server";
              version = vsrocq_version;
              src = ./language-server;
              nativeBuildInputs = [
                coq_8_18
              ];
              buildInputs =
                [
                  coq_8_18
                  dune_3
                ]
                ++ (with coq.ocamlPackages; [
                  lablgtk3-sourceview3
                  glib
                  pkgs.adwaita-icon-theme
                  wrapGAppsHook
                  ocaml
                  findlib
                  yojson
                  ppx_inline_test
                  ppx_assert
                  ppx_sexp_conv
                  ppx_deriving
                  ppx_optcomp
                  ppx_import
                  sexplib
                  ppx_yojson_conv
                  lsp
                  sel
                ]);
              propagatedBuildInputs= (with coq.ocamlPackages;
                [
                  zarith
                ]);
              preBuild = ''
                make dune-files
              '';
            };

        vsrocq-language-server-coq-8-19 =
          # Notice the reference to nixpkgs here.
          with import nixpkgs {inherit system;}; let
            ocamlPackages = ocaml-ng.ocamlPackages_4_14;
          in
            ocamlPackages.buildDunePackage {
              duneVersion = "3";
              pname = "vsrocq-language-server";
              version = vsrocq_version;
              src = ./language-server;
              nativeBuildInputs = [
                coq_8_19
              ];
              buildInputs =
                [
                  coq_8_19
                  dune_3
                ]
                ++ (with coq.ocamlPackages; [
                  lablgtk3-sourceview3
                  glib
                  pkgs.adwaita-icon-theme
                  wrapGAppsHook
                  ocaml
                  yojson
                  findlib
                  ppx_inline_test
                  ppx_assert
                  ppx_sexp_conv
                  ppx_deriving
                  ppx_optcomp
                  ppx_import
                  sexplib
                  ppx_yojson_conv
                  lsp
                  sel
                ]);
              propagatedBuildInputs= (with coq.ocamlPackages;
                [
                  zarith
                ]);
              preBuild = ''
                make dune-files
              '';
            };

        vsrocq-language-server-coq-8-20 =
          # Notice the reference to nixpkgs here.
          with import nixpkgs {inherit system;}; let
            ocamlPackages = ocaml-ng.ocamlPackages_4_14;
          in
            ocamlPackages.buildDunePackage {
              duneVersion = "3";
              pname = "vsrocq-language-server";
              version = vsrocq_version;
              src = ./language-server;
              nativeBuildInputs = [
                coq_8_20
              ];
              buildInputs =
                [
                  coq_8_20
                  dune_3
                ]
                ++ (with coq.ocamlPackages; [
                  lablgtk3-sourceview3
                  glib
                  pkgs.adwaita-icon-theme
                  wrapGAppsHook
                  ocaml
                  yojson
                  findlib
                  ppx_inline_test
                  ppx_assert
                  ppx_sexp_conv
                  ppx_deriving
                  ppx_optcomp
                  ppx_import
                  sexplib
                  ppx_yojson_conv
                  lsp
                  sel
                ]);
              propagatedBuildInputs= (with coq.ocamlPackages;
                [
                  zarith
                ]);
              preBuild = ''
                make dune-files
              '';
            };

        vsrocq-language-server-rocq-9 =
          # Notice the reference to nixpkgs here.
          with import nixpkgs {inherit system;}; let
            ocamlPackages = ocaml-ng.ocamlPackages_4_14;
          in
            ocamlPackages.buildDunePackage {
              duneVersion = "3";
              pname = "vsrocq-language-server";
              version = vsrocq_version;
              src = ./language-server;
              nativeBuildInputs = [
                rocq-core
              ];
              buildInputs =
                [
                  rocq-core
                  dune_3
                ]
                ++ (with coq.ocamlPackages; [
                  lablgtk3-sourceview3
                  glib
                  pkgs.adwaita-icon-theme
                  wrapGAppsHook
                  ocaml
                  yojson
                  findlib
                  ppx_inline_test
                  ppx_assert
                  ppx_sexp_conv
                  ppx_deriving
                  ppx_optcomp
                  ppx_import
                  sexplib
                  ppx_yojson_conv
                  lsp
                  sel
                ]);
              propagatedBuildInputs= (with coq.ocamlPackages;
                [
                  zarith
                ]);
              preBuild = ''
                make dune-files
              '';
            };

        vsrocq-language-server-rocq-9-1 =
          # Notice the reference to nixpkgs here.
          with import nixpkgs {inherit system;}; let
            ocamlPackages = ocaml-ng.ocamlPackages_4_14;
          in
            ocamlPackages.buildDunePackage {
              duneVersion = "3";
              pname = "vsrocq-language-server";
              version = vsrocq_version;
              src = ./language-server;
              nativeBuildInputs = [
                rocq-core
              ];
              buildInputs =
                [
                  rocq-core
                  dune_3
                ]
                ++ (with coq.ocamlPackages; [
                  lablgtk3-sourceview3
                  glib
                  pkgs.adwaita-icon-theme
                  wrapGAppsHook
                  ocaml
                  yojson
                  findlib
                  ppx_inline_test
                  ppx_assert
                  ppx_sexp_conv
                  ppx_deriving
                  ppx_optcomp
                  ppx_import
                  sexplib
                  ppx_yojson_conv
                  lsp
                  sel
                ]);
              propagatedBuildInputs= (with coq.ocamlPackages;
                [
                  zarith
                ]);
              preBuild = ''
                make dune-files
              '';
            };

        vsrocq-language-server-coq-master =
          # Notice the reference to nixpkgs here.
          with import nixpkgs {inherit system;}; let
            ocamlPackages = ocaml-ng.ocamlPackages_4_14;
          in
            ocamlPackages.buildDunePackage {
              duneVersion = "3";
              pname = "vsrocq-language-server";
              version = vsrocq_version;
              src = ./language-server;
              nativeBuildInputs = [
                rocq
              ];
              buildInputs =
                [
                  rocq
                  dune_3
                ]
                ++ (with coq.ocamlPackages; [
                  lablgtk3-sourceview3
                  glib
                  pkgs.adwaita-icon-theme
                  wrapGAppsHook
                  ocaml
                  yojson
                  findlib
                  ppx_inline_test
                  ppx_assert
                  ppx_sexp_conv
                  ppx_deriving
                  ppx_optcomp
                  ppx_import
                  sexplib
                  ppx_yojson_conv
                  lsp
                  sel
                ]);
              propagatedBuildInputs= (with coq.ocamlPackages;
                [
                  zarith
                ]);
              preBuild = ''
                make dune-files
              '';
            };

        vsrocq-client = with import nixpkgs {inherit system;}; let
          yarn_deps = name: (path: (mkYarnModules {
            pname = "${name}_yarn_deps";
            version = vsrocq_version;
            packageJSON = ./${path}/package.json;
            yarnLock = ./${path}/yarn.lock;
            yarnNix = ./${path}/yarn.nix;
          }));

          client_deps = yarn_deps "client" /client;
          goal_view_ui_deps = yarn_deps "goal_ui" /client/goal-view-ui;
          search_ui_deps = yarn_deps "search_ui" /client/search-ui;

          link_deps = x: (p: ''
            ln -s ${x}/node_modules ${p}
            export PATH=${x}/node_modules/.bin:$PATH
          '');

          links = [
            (link_deps client_deps ".")
            (link_deps goal_view_ui_deps "./goal-view-ui")
            (link_deps search_ui_deps "./search-ui")
          ];

          cmds = builtins.concatStringsSep "\n" links;

          src = ./client;

          nativeBuildInputs =
            [
              nodejs
              yarn
            ]
            ++ [client_deps goal_view_ui_deps search_ui_deps];

          installPrefix = "share/vscode/extensions/${vscodeExtUniqueId}";
        in {
          extension = pkgs.vscode-utils.buildVscodeExtension {
            inherit name vscodeExtName vscodeExtPublisher vscodeExtUniqueId src nativeBuildInputs;
            version = vsrocq_version;

            buildPhase =
              cmds
              + ''
                cd goal-view-ui
                yarn run build
                cd ../search-ui
                yarn run build
                cd ..
                webpack --mode=production --devtool hidden-source-map
              '';
          };
          vsix_archive = stdenv.mkDerivation {
            name = "vsrocq-client-vsix";

            unpackPhase = ''
              cp -r ${self.packages.${system}.vsrocq-client.extension}/share/vscode/extensions/${vscodeExtUniqueId}/* .
              ls -alt
              pwd
            '';

            nativeBuildInputs = [
              self.packages.${system}.vsrocq-client.extension
              client_deps
              nodejs
              yarn
            ];

            buildPhase = ''
              export PATH=${client_deps}/node_modules/.bin:$PATH
              bash -c "yes y | vsce package"
              mkdir -p $out/share/vscode/extensions
              cp *.vsix $out/share/vscode/extensions
            '';
          };
        };
      };

      devShells = {
        vsrocq-8-18 = with import nixpkgs {inherit system;};
          mkShell {
            buildInputs = 
              self.packages.${system}.vsrocq-client.extension.buildInputs
              ++ self.packages.${system}.vsrocq-language-server-coq-8-18.buildInputs
              ++ (with ocamlPackages; [
                ocaml-lsp
              ])
              ++ ([git]);
          };
        
        vsrocq-8-19 = with import nixpkgs {inherit system;}; let
          ocamlPackages = ocaml-ng.ocamlPackages_4_14;
        in
          mkShell {
            buildInputs =
              self.packages.${system}.vsrocq-client.extension.buildInputs
              ++ self.packages.${system}.vsrocq-language-server-coq-8-19.buildInputs
              ++ (with ocamlPackages; [
                ocaml-lsp
              ])
              ++ ([git]);
          };

        vsrocq-8-20 = with import nixpkgs {inherit system;}; let
          ocamlPackages = ocaml-ng.ocamlPackages_4_14;
        in
          mkShell {
            buildInputs =
              self.packages.${system}.vsrocq-client.extension.buildInputs
              ++ self.packages.${system}.vsrocq-language-server-coq-8-20.buildInputs
              ++ (with ocamlPackages; [
                ocaml-lsp
              ])
              ++ ([git]);
          };

        vsrocq-9 = with import nixpkgs {inherit system;}; let
          ocamlPackages = ocaml-ng.ocamlPackages_4_14;
        in
          mkShell {
            buildInputs =
              self.packages.${system}.vsrocq-client.extension.buildInputs
              ++ self.packages.${system}.vsrocq-language-server-rocq-9.buildInputs
              ++ (with ocamlPackages; [
                ocaml-lsp
              ])
              ++ ([git]);
            shellHook = ''
              export PATH="$PWD/language-server/.wrappers:$PATH"
            '';
          };

        vsrocq-9-1 = with import nixpkgs {inherit system;}; let
          ocamlPackages = ocaml-ng.ocamlPackages_4_14;
        in
          mkShell {
            buildInputs =
              self.packages.${system}.vsrocq-client.extension.buildInputs
              ++ self.packages.${system}.vsrocq-language-server-rocq-9-1.buildInputs
              ++ (with ocamlPackages; [
                ocaml-lsp
              ])
              ++ ([git]);
            shellHook = ''
              export PATH="$PWD/language-server/.wrappers:$PATH"
            '';
          };

        vsrocq-master = with import nixpkgs {inherit system;}; let
          ocamlPackages = ocaml-ng.ocamlPackages_4_14;
        in
          mkShell {
            buildInputs =
              self.packages.${system}.vsrocq-client.extension.buildInputs
              ++ self.packages.${system}.vsrocq-language-server-coq-master.buildInputs
              ++ (with ocamlPackages; [
                ocaml-lsp
              ])
              ++ ([git]);
          };

        default = with import nixpkgs {inherit system;}; let
          ocamlPackages = ocaml-ng.ocamlPackages_4_14;
        in
          mkShell {
            buildInputs =
              self.packages.${system}.vsrocq-client.extension.buildInputs
              ++ self.packages.${system}.vsrocq-language-server-coq-8-20.buildInputs
              ++ (with ocamlPackages; [
                ocaml-lsp
              ])
              ++ ([git]);
          };
      };
    });
}

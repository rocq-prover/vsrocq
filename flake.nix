{
  description = "VsRocq, a language server for Rocq based on LSP";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    rocq-master = { url = "github:rocq-prover/rocq/5358976838128ff6125ee64e3b3d08dac45fc2f3"; }; # Should be kept in sync with PIN_COQ in CI workflow
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
      name = "vsrocq-client";
      vscodeExtPublisher = "rocq-prover";
      vscodeExtName = "vsrocq";
      vscodeExtUniqueId = "rocq-prover.vsrocq";
      vsrocq_version = "2.5.0";
      rocq = let
        pkgs = import nixpkgs-unstable {inherit system;};
      in
        pkgs.rocq-core.override {
          version = rocq-master.outPath;
          customOCamlPackages = pkgs.ocaml-ng.ocamlPackages_4_14;
        };
    in rec {
      formatter = nixpkgs-unstable.legacyPackages.${system}.alejandra;

      packages = {
        default = self.packages.${system}.vsrocq-language-server-coq-8-20;

        vsrocq-language-server-coq-8-18 =
          # `lsp`'s propagated ppx_yojson_conv_lib/yojson otherwise resolve to
          # a different derivation than the scope's own copies, so findlib
          # sees duplicate META files; overriding yojson forces one fixed
          # point for the whole scope, matching the coq-9-1 stanza below.
          with import nixpkgs-unstable {inherit system;}; let
            ocamlPackages = coq_8_18.ocamlPackages.overrideScope (self: super: {
              yojson = super.yojson.overrideAttrs (_: {
                version = "2.2.2";
                __intentionallyOverridingVersion = true;
              });
            });
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
                ++ (with ocamlPackages; [
                  ocaml
                  findlib
                  yojson
                  ppx_inline_test
                  ppx_blob
                  ppx_assert
                  ppx_sexp_conv
                  ppx_deriving
                  ppx_optcomp
                  ppx_import
                  sexplib
                  ppx_yojson_conv
                  lsp
                  sel
                  memprof-limits
                ]);
              propagatedBuildInputs= (with ocamlPackages;
                [
                  zarith
                ]);
              preBuild = ''
                make dune-files
              '';
            };

        vsrocq-language-server-coq-8-19 =
          # See the coq-8-18 stanza for why yojson is overridden here.
          with import nixpkgs-unstable {inherit system;}; let
            ocamlPackages = coq_8_19.ocamlPackages.overrideScope (self: super: {
              yojson = super.yojson.overrideAttrs (_: {
                version = "2.2.2";
                __intentionallyOverridingVersion = true;
              });
            });
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
                ++ (with ocamlPackages; [
                  ocaml
                  yojson
                  findlib
                  ppx_inline_test
                  ppx_blob
                  ppx_assert
                  ppx_sexp_conv
                  ppx_deriving
                  ppx_optcomp
                  ppx_import
                  sexplib
                  ppx_yojson_conv
                  lsp
                  sel
                  memprof-limits
                ]);
              propagatedBuildInputs= (with ocamlPackages;
                [
                  zarith
                ]);
              preBuild = ''
                make dune-files
              '';
            };

        vsrocq-language-server-coq-8-20 =
          # See the coq-8-18 stanza for why yojson is overridden here.
          with import nixpkgs-unstable {inherit system;}; let
            ocamlPackages = coq_8_20.ocamlPackages.overrideScope (self: super: {
              yojson = super.yojson.overrideAttrs (_: {
                version = "2.2.2";
                __intentionallyOverridingVersion = true;
              });
            });
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
                ++ (with ocamlPackages; [
                  ocaml
                  yojson
                  findlib
                  ppx_inline_test
                  ppx_blob
                  ppx_assert
                  ppx_sexp_conv
                  ppx_deriving
                  ppx_optcomp
                  ppx_import
                  sexplib
                  ppx_yojson_conv
                  lsp
                  sel
                  memprof-limits
                ]);
              propagatedBuildInputs= (with ocamlPackages;
                [
                  zarith
                ]);
              preBuild = ''
                make dune-files
              '';
            };

        vsrocq-language-server-rocq-9 =
          # See the coq-8-18 stanza for why yojson is overridden here.
          with import nixpkgs-unstable {inherit system;}; let
            ocamlPackages = coq_9_0.ocamlPackages.overrideScope (self: super: {
              yojson = super.yojson.overrideAttrs (_: {
                version = "2.2.2";
                __intentionallyOverridingVersion = true;
              });
            });
          in
            ocamlPackages.buildDunePackage {
              duneVersion = "3";
              pname = "vsrocq-language-server";
              version = vsrocq_version;
              src = ./language-server;
              nativeBuildInputs = [
                coq_9_0
              ];
              buildInputs =
                [
                  coq_9_0
                  dune_3
                ]
                ++ (with ocamlPackages; [
                  ocaml
                  yojson
                  findlib
                  ppx_inline_test
                  ppx_blob
                  ppx_assert
                  ppx_sexp_conv
                  ppx_deriving
                  ppx_optcomp
                  ppx_import
                  sexplib
                  ppx_yojson_conv
                  lsp
                  sel
                  memprof-limits
                ]);
              propagatedBuildInputs= (with ocamlPackages;
                [
                  zarith
                ]);
              preBuild = ''
                make dune-files
              '';
            };

        vsrocq-language-server-rocq-9-1 =
          # Notice the reference to nixpkgs here.
          with import nixpkgs-unstable {inherit system;}; let
            # `lsp` hard-requires yojson_2 (2.2.2) while everything else in this
            # OCaml 4.14 scope defaults to yojson 3.0.0; unify on 2.2.2 to avoid
            # two conflicting yojson copies in the same build environment.
            ocamlPackages = coq_9_1.ocamlPackages.overrideScope (self: super: {
              yojson = super.yojson.overrideAttrs (_: {
                version = "2.2.2";
                __intentionallyOverridingVersion = true;
              });
            });
          in
            ocamlPackages.buildDunePackage {
              duneVersion = "3";
              pname = "vsrocq-language-server";
              version = vsrocq_version;
              src = ./language-server;
              nativeBuildInputs = [
                coq_9_1
              ];
              buildInputs =
                [
                  coq_9_1
                  dune_3
                ]
                ++ (with ocamlPackages; [
                  ocaml
                  yojson
                  findlib
                  ppx_inline_test
                  ppx_blob
                  ppx_assert
                  ppx_sexp_conv
                  ppx_yojson_conv
                  ppx_deriving
                  ppx_optcomp
                  ppx_import
                  sexplib
                  lsp
                  sel
                  # nixpkgs pins memprof-limits to 0.2.1, which does not build
                  # against OCaml >= 5 (Gc.Memprof API changes). 0.3.0 does.
                  (memprof-limits.overrideAttrs (old: {
                    version = "0.3.0";
                    src = fetchFromGitLab {
                      owner = "gadmm";
                      repo = "memprof-limits";
                      rev = "v0.3.0";
                      hash = "sha256-k/uB1jDQtE/PkVPU8zg8cpOmlPttTWVpKerQ0HuWfuI=";
                    };
                    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ cppo ];
                    meta = old.meta // { broken = false; };
                  }))
                ]);
              propagatedBuildInputs= (with ocamlPackages;
                [
                  zarith
                ]);
              preBuild = ''
                make dune-files
              '';
            };

          vsrocq-language-server-rocq-9-2 =
          # Notice the reference to nixpkgs here.
          with import nixpkgs-unstable {inherit system;}; let
            ocamlPackages = coq_9_2.ocamlPackages;
          in
            ocamlPackages.buildDunePackage {
              duneVersion = "3";
              pname = "vsrocq-language-server";
              version = vsrocq_version;
              src = ./language-server;
              nativeBuildInputs = [
                coq_9_2
              ];
              buildInputs =
                [
                  coq_9_2
                  dune_3
                ]
                ++ (with ocamlPackages; [
                  ocaml
                  yojson
                  findlib
                  ppx_inline_test
                  ppx_assert
                  ppx_sexp_conv
                  ppx_yojson_conv
                  ppx_deriving
                  ppx_optcomp
                  ppx_import
                  sexplib
                  lsp
                  sel
                  # nixpkgs pins memprof-limits to 0.2.1, which does not build
                  # against OCaml >= 5 (Gc.Memprof API changes). 0.3.0 does.
                  (memprof-limits.overrideAttrs (old: {
                    version = "0.3.0";
                    src = fetchFromGitLab {
                      owner = "gadmm";
                      repo = "memprof-limits";
                      rev = "v0.3.0";
                      hash = "sha256-k/uB1jDQtE/PkVPU8zg8cpOmlPttTWVpKerQ0HuWfuI=";
                    };
                    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ cppo ];
                    meta = old.meta // { broken = false; };
                  }))
                ]);
              propagatedBuildInputs= (with ocamlPackages;
                [
                  zarith
                ]);
              preBuild = ''
                make dune-files
              '';
            };

          vsrocq-language-server-rocq-9-3 =
          # Notice the reference to nixpkgs here.
          with import nixpkgs-unstable {inherit system;}; let
            ocamlPackages = coq_9_3.ocamlPackages;
          in
            ocamlPackages.buildDunePackage {
              duneVersion = "3";
              pname = "vsrocq-language-server";
              version = vsrocq_version;
              src = ./language-server;
              nativeBuildInputs = [
                coq_9_3
              ];
              buildInputs =
                [
                  coq_9_3
                  dune_3
                ]
                ++ (with ocamlPackages; [
                  ocaml
                  yojson
                  findlib
                  ppx_inline_test
                  ppx_assert
                  ppx_sexp_conv
                  ppx_yojson_conv
                  ppx_deriving
                  ppx_optcomp
                  ppx_import
                  sexplib
                  lsp
                  sel
                  # nixpkgs pins memprof-limits to 0.2.1, which does not build
                  # against OCaml >= 5 (Gc.Memprof API changes). 0.3.0 does.
                  (memprof-limits.overrideAttrs (old: {
                    version = "0.3.0";
                    src = fetchFromGitLab {
                      owner = "gadmm";
                      repo = "memprof-limits";
                      rev = "v0.3.0";
                      hash = "sha256-k/uB1jDQtE/PkVPU8zg8cpOmlPttTWVpKerQ0HuWfuI=";
                    };
                    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ cppo ];
                    meta = old.meta // { broken = false; };
                  }))
                ]);
              propagatedBuildInputs= (with ocamlPackages;
                [
                  zarith
                ]);
              preBuild = ''
                make dune-files
              '';
            };

        vsrocq-language-server-coq-master =
          # Notice the reference to nixpkgs here.
          with import nixpkgs-unstable {inherit system;}; let
            # `lsp` hard-requires yojson_2 (2.2.2) while everything else in this
            # OCaml 4.14 scope defaults to yojson 3.0.0; unify on 2.2.2 to avoid
            # two conflicting yojson copies in the same build environment.
            ocamlPackages = rocq.ocamlPackages.overrideScope (self: super: {
              yojson = super.yojson.overrideAttrs (_: {
                version = "2.2.2";
                __intentionallyOverridingVersion = true;
              });
            });
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
                ++ (with ocamlPackages; [
                  ocaml
                  yojson
                  findlib
                  ppx_inline_test
                  ppx_blob
                  ppx_assert
                  ppx_sexp_conv
                  ppx_yojson_conv
                  ppx_deriving
                  ppx_optcomp
                  ppx_import
                  sexplib
                  lsp
                  sel
                  # nixpkgs pins memprof-limits to 0.2.1, which does not build
                  # against OCaml >= 5 (Gc.Memprof API changes). 0.3.0 does.
                  (memprof-limits.overrideAttrs (old: {
                    version = "0.3.0";
                    src = fetchFromGitLab {
                      owner = "gadmm";
                      repo = "memprof-limits";
                      rev = "v0.3.0";
                      hash = "sha256-k/uB1jDQtE/PkVPU8zg8cpOmlPttTWVpKerQ0HuWfuI=";
                    };
                    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ cppo ];
                    meta = old.meta // { broken = false; };
                  }))
                ]);
              propagatedBuildInputs= (with ocamlPackages;
                [
                  zarith
                ]);
              preBuild = ''
                make dune-files
              '';
            };

        vsrocq-client = with import nixpkgs-unstable {inherit system;}; let
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
        vsrocq-8-18 = with import nixpkgs-unstable {inherit system;};
          mkShell {
            buildInputs = 
              self.packages.${system}.vsrocq-client.extension.buildInputs
              ++ self.packages.${system}.vsrocq-language-server-coq-8-18.buildInputs
              ++ (with ocamlPackages; [
                ocaml-lsp
              ])
              ++ ([git]);
          };
        
        vsrocq-8-19 = with import nixpkgs-unstable {inherit system;};
          mkShell {
            buildInputs =
              self.packages.${system}.vsrocq-client.extension.buildInputs
              ++ self.packages.${system}.vsrocq-language-server-coq-8-19.buildInputs
              ++ ([git]);
          };

        vsrocq-8-20 = with import nixpkgs-unstable {inherit system;};
          mkShell {
            buildInputs =
              self.packages.${system}.vsrocq-client.extension.buildInputs
              ++ self.packages.${system}.vsrocq-language-server-coq-8-20.buildInputs
              ++ ([git]);
          };

        vsrocq-9 = with import nixpkgs-unstable {inherit system;};
          mkShell {
            buildInputs =
              self.packages.${system}.vsrocq-client.extension.buildInputs
              ++ self.packages.${system}.vsrocq-language-server-rocq-9.buildInputs
              ++ ([git]);
            shellHook = ''
              export PATH="$PWD/language-server/.wrappers:$PATH"
            '';
          };

        vsrocq-9-1 = with import nixpkgs-unstable {inherit system;};
          mkShell {
            buildInputs =
              self.packages.${system}.vsrocq-client.extension.buildInputs
              ++ self.packages.${system}.vsrocq-language-server-rocq-9-1.buildInputs
              ++ ([git]);
            shellHook = ''
              export PATH="$PWD/language-server/.wrappers:$PATH"
            '';
          };

        vsrocq-9-2 = with import nixpkgs-unstable {inherit system;};
          mkShell {
            buildInputs =
              self.packages.${system}.vsrocq-client.extension.buildInputs
              ++ self.packages.${system}.vsrocq-language-server-rocq-9-2.buildInputs
              ++ ([git]);
            shellHook = ''
              export PATH="$PWD/language-server/.wrappers:$PATH"
            '';
          };

        vsrocq-9-3 = with import nixpkgs-unstable {inherit system;};
          mkShell {
            buildInputs =
              self.packages.${system}.vsrocq-client.extension.buildInputs
              ++ self.packages.${system}.vsrocq-language-server-rocq-9-3.buildInputs
              ++ ([git]);
            shellHook = ''
              export PATH="$PWD/language-server/.wrappers:$PATH"
            '';
          };

        vsrocq-master = with import nixpkgs-unstable {inherit system;}; let
          ocamlPackages = rocq.ocamlPackages;
        in
          mkShell {
            buildInputs =
              self.packages.${system}.vsrocq-client.extension.buildInputs
              ++ self.packages.${system}.vsrocq-language-server-coq-master.buildInputs
              ++ ([git]);
          };

        default = with import nixpkgs-unstable {inherit system;};
          mkShell {
            buildInputs =
              self.packages.${system}.vsrocq-client.extension.buildInputs
              ++ self.packages.${system}.vsrocq-language-server-coq-8-20.buildInputs
              ++ ([git]);
          };
      };
    });
}

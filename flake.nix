{
  description = "VsRocq, a language server for Rocq based on LSP";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    rocq-master = { url = "github:rocq-prover/rocq/eebacb3bb172082ca7403525483510ab85212a08"; }; # Should be kept in sync with PIN_COQ in CI workflow
    rocq-master.inputs.nixpkgs.follows = "nixpkgs";
    rocq-master.inputs.flake-utils.follows = "flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-unstable,
    flake-utils,
    rocq-master,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      name = "vsrocq-client";
      vscodeExtPublisher = "rocq-prover";
      vscodeExtName = "vsrocq";
      vscodeExtUniqueId = "rocq-prover.vsrocq";
      vsrocq_version = "2.4.3";
      rocq = (import nixpkgs {inherit system;}).rocq-core.override { version = rocq-master.outPath; };
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
                  memprof-limits
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
                  memprof-limits
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
                  memprof-limits
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
                coq_9_0
              ];
              buildInputs =
                [
                  coq_9_0
                  dune_3
                ]
                ++ (with coq.ocamlPackages; [
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
                  memprof-limits
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
          with import nixpkgs-unstable {inherit system;}; let
            ocamlPackages = ocaml-ng.ocamlPackages_4_14;
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
                ++ (with coq.ocamlPackages; [
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
                  memprof-limits
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
                  memprof-limits
                ]);
              propagatedBuildInputs= (with coq.ocamlPackages;
                [
                  zarith
                ]);
              preBuild = ''
                make dune-files
              '';
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

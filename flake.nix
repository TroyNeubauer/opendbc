{
  description = "flake for opendbc joystick example – pure Nix packaging";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
  let
    system         = "x86_64-linux";
    pkgs           = import nixpkgs { inherit system; };
    python         = pkgs.python312;
    pythonPackages = pkgs.python312Packages;

    # 1) Build the PyPI 'inputs' package
    inputsSrc = pkgs.fetchPypi {
      pname   = "inputs";
      version = "0.5";
      sha256  = "sha256-ox1blqNSXxIy8ya+nnzozK+HPGsfuE2fPJvD15sj6uQ=";
    };
    inputsPkg = pythonPackages.buildPythonPackage rec {
      pname   = "inputs";
      version = "0.5";
      src     = inputsSrc;
      format  = "setuptools";
      doCheck = false;
    };

    opendbcSrc = pkgs.fetchFromGitHub {
      owner = "commaai";
      repo  = "opendbc";
      rev = "v0.2.1";
      sha256 = "sha256-bA2FJYy7rIkDfmLClXQz0qECBzEMKfbpglBEiRWUnE4=";
    };
    opendbcPkg = pythonPackages.buildPythonPackage rec {
      pname = "opendbc";
      version = "0.2.1";
      src = opendbcSrc;
      format = "other";

      # Build‑time tools: Python‑SCons, Cython, NumPy, setuptools
      nativeBuildInputs = [
        pkgs.scons
        pythonPackages.cython
        pythonPackages.setuptools
        pythonPackages.distutils
      ];

      propagatedBuildInputs = with pythonPackages; [
        numpy
        cantools
        # "python-can"
        inputsPkg
        crcmod
        tqdm
        pycapnp
        pycryptodome
      ];

      doCheck = false;

      patchPhase = ''
        # Patch SConstruct so that it uses numpy from nix nistead of dynamic path hack
        sed -i 's/^import numpy as np/# &/' SConstruct
        sed -i 's/np.get_include()/python_path/' SConstruct

        # Patch schebangs into generator files so that they run properly
        sed -i "1s|.*|#!${python.interpreter}|" opendbc/dbc/generator/*/*.py

        # Export repo root so sub-scripts can use import opendbc.*
        export PYTHONPATH="$PWD:$PYTHONPATH"
        ${python.interpreter} opendbc/dbc/generator/generator.py .
      '';

      buildPhase = ''
        scons -Q -f SConstruct
      '';

      installPhase = ''
        mkdir -p $out/${python.sitePackages}
        cp -r opendbc $out/${python.sitePackages}/
      '';
    };

    pandaSrc = pkgs.fetchgit {
      url = "https://github.com/commaai/panda.git";
      rev = "ca603115cb3f570e4d8ba20607ac24b4352ddbd6";
      sha256 = "sha256-9LQrNFer4rghHmOHgj/kZjDIJhln8sRmducI3kBHYZU=";
    };
    pandaPkg = pythonPackages.buildPythonPackage rec {
      pname = "panda";
      version = "2025-07-20";
      src = pandaSrc;
      format = "setuptools";

      nativeBuildInputs = [ pkgs.scons ];
      propagatedBuildInputs = [ opendbcPkg ];
      doCheck = false;

      buildPhase = ''
        ${python.interpreter} -m SCons -Q
      '';
      installPhase = ''
        mkdir -p $out/${python.sitePackages}
        cp -r python $out/${python.sitePackages}/panda
      '';
    };

    # 4) Combine everything into one Python environment
    pythonEnv = python.withPackages (ps: with ps; [
      cantools
      "python-can"
      inputsPkg
      numpy
      crcmod
      tqdm
      pycapnp
      setuptools
      pycryptodome
      libusb1
      opendbcPkg
      pandaPkg
    ]);

  in {
    packages.${system}.opendbc = opendbcPkg;
    devShells.${system}.default = pkgs.mkShell {
      buildInputs = [
        pythonEnv
        pkgs.git
      ];
      shellHook = ''
        echo "🐍 devShell ready – opendbc, panda & python-can are installed"
      '';
    };
  };
}


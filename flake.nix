{
  description = "Apache Hive is a SQL interface to tables in HDFS.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.11";

    # nixpkgs.url = "/home/sahiti/work/nixpkgs";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils }:
    utils.lib.eachSystem [ utils.lib.system.x86_64-linux ] # utils.lib.defaultSystems
      (system: rec {
        legacyPackages = import nixpkgs { inherit system; };
        defaultPackage = legacyPackages.callPackage ./default.nix { jdk = legacyPackages.jdk8; }; # TODO make jdk version configurable
        packages = {
          oozie = legacyPackages.callPackage ./oozie.nix { jdk = legacyPackages.jdk8; };
        };
        checks = {
          standalone-tests = import ./test.nix {
            makeTest = import (nixpkgs + "/nixos/tests/make-test-python.nix");
            pkgs = legacyPackages;
            flake = self;
            package = defaultPackage;
          };

          hadoop-tests = import ./full-hadoop-test.nix {
            makeTest = import (nixpkgs + "/nixos/tests/make-test-python.nix");
            pkgs = legacyPackages;
            flake = self;
            package = defaultPackage;

          };

          hadoop-integration-tests = import ./test-with-hadoop.nix {
            makeTest = import (nixpkgs + "/nixos/tests/make-test-python.nix");
            pkgs = legacyPackages;
            flake = self;
            package = defaultPackage;
          };

          kerberos-integration-tests = import ./test-with-kerberos.nix {
            makeTest = import (nixpkgs + "/nixos/tests/make-test-python.nix");
            pkgs = legacyPackages;
            flake = self;
            package = defaultPackage;
          };
        };

      }) // {
      nixosModules = {
        hiveserver = ./hiveserver-module.nix;
      };
    };
}


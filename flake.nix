{
  description = "Apache Hive is a SQL interface to tables in HDFS.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.11";

    # nixpkgs.url = "/home/sahiti/work/nixpkgs";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils }: utils.lib.eachDefaultSystem
    (system:
      let pkgs = import nixpkgs { inherit system; };
      in
      rec {
        defaultPackage = packages.hive;
        packages = {
          hive = pkgs.callPackage ./default.nix { jdk = pkgs.jdk8; }; # TODO make jdk version configurable
          # oozie = pkgs.callPackage ./oozie.nix { jdk = pkgs.jdk8; }; not packaging oozie. it isn't even compatible with hadoop 3.
        };
        checks =
          let test = name: file: import file {
            inherit pkgs;
            makeTest = import (nixpkgs + "/nixos/tests/make-test-python.nix");
            flake = self;
            package = defaultPackage;
          };
          in
          pkgs.lib.mapAttrs test {
            standalone-tests = ./test.nix;
            hadoop-tests = ./full-hadoop-test.nix;
            hadoop-integration-tests = ./test-with-hadoop.nix;
            kerberos-integration-tests = ./test-with-kerberos.nix;
          };

      }) // {
    nixosModules = {
      hiveserver = ./hiveserver-module.nix;
    };
  };
}


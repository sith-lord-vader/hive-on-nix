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
      nixosModule = { config, lib, pkgs, ... }:

        with lib;
        let cfg = config.services.hadoop.hiveserver;
        in
        {

          options.services.hadoop.hiveserver = {
            enable = mkEnableOption "enable hiveserver";

            metastore = {
              enable = mkEnableOption "enable metastore. not actually used, right now metastore is active wherever server is.";
              openFirewall = mkEnableOption "open firewall ports for metastore";
            };
            openFirewall = mkEnableOption "open firewall ports for hiveserver webUI and JDBC connection.";

            hiveSite = mkOption {
              default = { };
              type = types.attrsOf types.anything;
              example = literalExpression ''
                {
                  "fs.defaultFS" = "hdfs://localhost";
                }
              '';
              description = ''
                Hive configuration hive-site.xml definition
                <link xlink:href="https://cwiki.apache.org/confluence/display/Hive/AdminManual+Configuration"/>
              '';
            };
            hiveSiteDefault = mkOption {
              default = {
                "hive.server2.enable.doAs" = "false";
                # https://issues.apache.org/jira/browse/HIVE-19740
                "hadoop.proxyuser.hive.hosts" = "HS2_HOST";
                "hadoop.proxyuser.hive.groups" = "*";
              };
              type = types.attrsOf types.anything;
              example = literalExpression ''
                {
                  "fs.defaultFS" = "hdfs://localhost";
                }
              '';
              description = ''
                Hive configuration hive-site.xml definition
                <link xlink:href="https://cwiki.apache.org/confluence/display/Hive/AdminManual+Configuration"/>
              '';
            };

            gatewayRole.enable = mkEnableOption "gateway role for deploying hive configs to toher nodes";

          };

          config = mkMerge [

            (mkIf cfg.gatewayRole.enable {
              users.users.hive = {
                description = "hive user";
                isSystemUser = true;
                group = "hadoop";
              };
              environment.systemPackages = [
                self.defaultPackage.${config.nixpkgs.system}
              ];
            })

            (mkIf cfg.enable {
              environment.systemPackages = [
                self.defaultPackage.${config.nixpkgs.system}
              ];
              networking.firewall.allowedTCPPorts = (mkIf cfg.openFirewall [ 10000 10001 10002 14000 ]) // (mkIf cfg.metastore.openFirewall [ 9083 ]);

              users.users.hive = {
                description = "hive user";
                isSystemUser = true;
                group = "hadoop";
              };

              services.hadoop = {
                extraConfDirs =
                  let
                    propertyXml = name: value: lib.optionalString (value != null) ''
                      <property>
                        <name>${name}</name>
                        <value>${builtins.toString value}</value>
                      </property>
                    '';
                    siteXml = fileName: properties: pkgs.writeTextDir fileName ''
                      <?xml version="1.0" encoding="UTF-8" standalone="no"?>
                      <!-- generated by NixOS -->
                      <configuration>
                        ${builtins.concatStringsSep "\n" (pkgs.lib.mapAttrsToList propertyXml properties)}
                      </configuration>
                    '';
                  in
                  [
                    (pkgs.runCommand "hive-conf" { }
                      (with cfg; ''
                        mkdir -p $out/
                        cp ${siteXml "hive-site.xml" (hiveSiteDefault // hiveSite)}/* $out/
                        cp ${siteXml "metastore-site.xml" (hiveSiteDefault // hiveSite)}/* $out/
                      ''))
                  ];

                gatewayRole.enable = true;
              };
              systemd.services = {
                hive-init = {
                  wantedBy = [ "multi-user.target" ];
                  path = [ pkgs.hadoop pkgs.sudo config.krb5.kerberos ];
                  script = with pkgs; ''
                    # in future to be escaped with a kerberos enable option
                    # kinit -k -t /var/security/keytab/hiveserver.service.keytab hive/hiveserver

                    sudo -u hdfs hadoop fs -mkdir -p /home/hive || true
                    sudo -u hdfs hadoop fs -chown hive:hadoop /home/hive || true

                    sudo -u hdfs hadoop fs -mkdir /tmp || true
                    sudo -u hdfs hadoop fs -chown hdfs:hadoop /tmp || true
                    sudo -u hdfs hadoop fs -chmod g+w /tmp || true

                    sudo -u hdfs hadoop fs -mkdir -p /user/hive || true
                    sudo -u hdfs hadoop fs -chown hive:hadoop /user/hive || true

                    sudo -u hdfs hadoop fs -mkdir /user/hive/warehouse || true
                    sudo -u hdfs hadoop fs -chown hive:hadoop /user/hive/warehouse || true
                    sudo -u hdfs hadoop fs -chmod g+w /user/hive/warehouse || true

                    ${pkgs.coreutils}/bin/mkdir /var/run/hive || true
                    ${pkgs.coreutils}/bin/chown hive:hadoop /var/run/hive || true

                  '';
                  serviceConfig = {

                    Type = "oneshot";
                    # The below are the instructions to initialize Hive resoruces given in https://cwiki.apache.org/confluence/display/Hive/GettingStarted#GettingStarted-RunningHiveServer2andBeeline.
                  };
                };

                hiveserver = {
                  wantedBy = [ "multi-user.target" ];
                  after = [ "network.target" "hive-init.service" ];
                  environment =
                    {
                      HADOOP_CONF_DIR = "/etc/hadoop-conf";
                    };
                  script = ''
                    hiveserver2 --hiveconf hive.root.logger=INFO,console
                  '';
                  path = [ pkgs.sudo self.defaultPackage.${config.nixpkgs.system} pkgs.coreutils ];
                  serviceConfig = {
                    User = "hive";
                  };
                };

                hivemetastore = {
                  wantedBy = [ "multi-user.target" ];
                  after = [ "network.target" "hive-init.service" ];
                  environment =
                    {
                      HADOOP_CONF_DIR = "/etc/hadoop-conf";
                    };
                  script = ''
                  hive --service metastore --hiveconf hive.root.logger=INFO,console
                  '';
                  path = [ pkgs.sudo self.defaultPackage.${config.nixpkgs.system} pkgs.coreutils ];
                  serviceConfig = {
                    User = "hive";
                  };
                };
              };
            })
          ];
        };
    };
}


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
			kerberos = ./kerberos-module.nix;
			hadoop-kerberos = ./hadoop-kerberos-module.nix;
			hiveserver = { config, lib, pkgs, ... }:

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

            user = mkOption {
              type = types.str;
              default = "hive";
              description = "user that hive services run with";
            };
            group = mkOption {
              type = types.str;
              default = "hadoop";
              description = "group that hive services run with";
            };

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
								"hive.metastore.event.db.notification.api.auth" = "false";
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
            extraEnv = mkOption {
              default = {
              };
              type = types.attrsOf types.anything;
              description = lib.mdDoc ''
                Extra envs.
              '';
            };

						gatewayRole.enable = mkEnableOption "gateway role for deploying hive configs to toher nodes";

					};

					config = mkMerge [

						(mkIf cfg.gatewayRole.enable {
							users.users.${config.services.hadoop.hiveserver.user} = {
								description = "hive user";
								isSystemUser = true;
								group = config.services.hadoop.hiveserver.group;
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

							users.users.${config.services.hadoop.hiveserver.user} = {
								description = "hive user";
								isSystemUser = true;
								group = config.services.hadoop.hiveserver.group;
							};

							services.hadoop = {
								extraConfDirs = let
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
									path = [ pkgs.hadoop pkgs.sudo pkgs.coreutils config.krb5.kerberos ];
									script = ''
										# in future to be escaped with a kerberos enable option
										# kinit -k -t /var/security/keytab/hiveserver.service.keytab hive/hiveserver

										sudo -u hdfs hadoop fs -mkdir -p /home/hive || true
										sudo -u hdfs hadoop fs -chown ${config.services.hadoop.hiveserver.user}:${config.services.hadoop.hiveserver.group} /home/hive || true

										sudo -u hdfs hadoop fs -mkdir /tmp || true
										sudo -u hdfs hadoop fs -chown hdfs:${config.services.hadoop.hiveserver.group} /tmp || true
										sudo -u hdfs hadoop fs -chmod g+w /tmp || true

										sudo -u hdfs hadoop fs -mkdir -p /user/hive || true
										sudo -u hdfs hadoop fs -chown ${config.services.hadoop.hiveserver.user}:${config.services.hadoop.hiveserver.group} /user/hive || true

										sudo -u hdfs hadoop fs -mkdir /user/hive/warehouse || true
										sudo -u hdfs hadoop fs -chown ${config.services.hadoop.hiveserver.user}:${config.services.hadoop.hiveserver.group} /user/hive/warehouse || true
										sudo -u hdfs hadoop fs -chmod g+w /user/hive/warehouse || true

										mkdir /var/run/hive || true
										chown ${config.services.hadoop.hiveserver.user}:${config.services.hadoop.hiveserver.group} /var/run/hive || true
									'';
									serviceConfig = {
										Type = "oneshot";
										# The below are the instructions to initialize Hive resoruces given in https://cwiki.apache.org/confluence/display/Hive/GettingStarted#GettingStarted-RunningHiveServer2andBeeline.
									};
								};

								hiveserver = {
									wantedBy = [ "multi-user.target" ];
									after = [ "network.target" "hive-init.service" ];
                  environment = { HADOOP_CONF_DIR = "/etc/hadoop-conf"; } // cfg.extraEnv;
									script = ''
										hiveserver2 --hiveconf hive.root.logger=INFO,console
									'';
									path = with pkgs; [ self.defaultPackage.${config.nixpkgs.system} sudo coreutils bash which gawk psutils ];
									serviceConfig = {
										User = config.services.hadoop.hiveserver.user;
									};
								};

								hivemetastore = {
									wantedBy = [ "multi-user.target" ];
									after = [ "network.target" "hive-init.service" ];
									environment.HADOOP_CONF_DIR = "/etc/hadoop-conf";
									script = ''
										hive --service metastore --hiveconf hive.root.logger=INFO,console
									'';
									path = with pkgs; [ self.defaultPackage.${config.nixpkgs.system} sudo coreutils bash which gawk psutils ];
									serviceConfig = {
										User = config.services.hadoop.hiveserver.user;
									};
								};
							};
						})
					];
				};
		};
	};
}

{
  description = "Apache Hive is a SQL interface to tables in HDFS.";

  inputs = {
		
    nixpkgs.url = "/home/sahiti/work/nixpkgs";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils }:
		utils.lib.eachSystem [ utils.lib.system.x86_64-linux ] # utils.lib.defaultSystems
		(system: rec {
			legacyPackages = import nixpkgs {inherit system;};
			defaultPackage = legacyPackages.callPackage ./default.nix {};
			packages = {
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
			nixosModule = {config, lib, pkgs,...}: with lib;  {

				options.services.hiveserver.enable = mkEnableOption {
					default = false;
					description = "enable hiveserver";
				};
				
				config = mkIf config.services.hiveserver.enable {
					environment.systemPackages = [self.defaultPackage.${config.nixpkgs.system}];
					networking.firewall.allowedTCPPorts = [10000 10001 10002];
					systemd.services.hiveserver =  {
						wantedBy = [ "multi-user.target" ];
						after = ["network.target"];
						environment = {
							HADOOP_CONF_DIR = "/etc/hadoop-conf";
						};				
						path = [ self.defaultPackage.${config.nixpkgs.system} pkgs.coreutils ];
						serviceConfig = {
							ExecStart = ''
							${self.defaultPackage.${config.nixpkgs.system}}/bin/hiveserver2
						'';
# The below are the instructions to initialize Hive resoruces given in https://cwiki.apache.org/confluence/display/Hive/GettingStarted#GettingStarted-RunningHiveServer2andBeeline. 
# 							ExecStartPre = ''
# # echo "hadoop home is" $HADOOP_HOME
# $HADOOP_HOME/bin/hadoop fs -mkdir       /tmp
# $HADOOP_HOME/bin/hadoop fs -mkdir       /user/hive/warehouse
# $HADOOP_HOME/bin/hadoop fs -chmod g+w   /tmp
# $HADOOP_HOME/bin/hadoop fs -chmod g+w   /user/hive/warehouse
# '';
						};
					};
				};
			};
		};
}

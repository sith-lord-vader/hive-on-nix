{config, lib, pkgs,...}:

with lib;
{

	options.services.hiveserver = {
		enable = mkEnableOption {
			default = false;
			description = "enable hiveserver";
		};
		hiveSite = {
			default = {};
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

		gatewayRole = mkEnableOption "gateway role for deploying hive configs to toher nodes";
		
	};
	
	config = mkMerge [

		(mkIf config.services.gatewayRole.enable {
			users.users.hive = {
				description = "hive user";
				isSystemUser = true;
				group = "hadoop";
			};
		})
		
		(mkIf config.services.hiveserver.enable {
			environment.systemPackages = [self.defaultPackage.${config.nixpkgs.system}];
			networking.firewall.allowedTCPPorts = [10000 10001 10002 14000];

			services.hadoop.gatewayRole.enable = true;
			users.users.hive = {
				description = "hive user";
				isSystemUser = true;
				group = "hadoop";
			};
			
			systemd.services = {
				hive-init = {
					before = [ "hiveserver.service" ];
					path = [ pkgs.hadoop ];
					serviceConfig = {

						Type = "oneshot";
						# The below are the instructions to initialize Hive resoruces given in https://cwiki.apache.org/confluence/display/Hive/GettingStarted#GettingStarted-RunningHiveServer2andBeeline.
						ExecStart = with pkgs; ''
hadoop fs -mkdir       /tmp
hadoop fs -mkdir       /user/hive/warehouse
hadoop fs -chmod g+w   /tmp
hadoop fs -chmod g+w   /user/hive/warehouse
'';
						User = "hdfs";
					};
				};
				
				hiveserver =  {
					wantedBy = [ "multi-user.target" ];
					after = ["network.target" "hive-init.service" ];
					environment = {
						HADOOP_CONF_DIR = "/etc/hadoop-conf";
					};				
					path = [ self.defaultPackage.${config.nixpkgs.system} pkgs.coreutils ];
					serviceConfig = {
						ExecStart = ''
							${self.defaultPackage.${config.nixpkgs.system}}/bin/hiveserver2
						'';
						User = "hive";
					};
				};
			};
		})
	];
}

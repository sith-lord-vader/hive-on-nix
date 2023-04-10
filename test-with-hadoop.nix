{ flake  ? builtins.getFlake (toString ./.)
, pkgs ? flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem}
, makeTest ? pkgs.callPackage (flake.inputs.nixpkgs + "/nixos/tests/make-test-python.nix")
, package ? flake.defaultPackage.${builtins.currentSystem}
}:




makeTest {
  name = "hive-with-hadoop";
	nodes = {
		namenode = {pkgs, ...}: {
			imports = [flake.nixosModules.hiveserver];
			services.hadoop.hiveserver.gatewayRole.enable = true;
      services.hadoop = {
        package = pkgs.hadoop;
        hdfs = {
          namenode = {
            enable = true;
            formatOnInit = true;
						openFirewall = true;
          };
        };
        coreSite = {
          "fs.defaultFS" = "hdfs://namenode:8020";
          "hadoop.proxyuser.httpfs.groups" = "*";
          "hadoop.proxyuser.httpfs.hosts" = "*";
        };
      };
    };
		
    datanode = {pkgs, ...}: {
			imports = [flake.nixosModule];
			services.hadoop.hiveserver.gatewayRole.enable = true;

      services.hadoop = {
        package = pkgs.hadoop;
        hdfs.datanode = {
					enable = true;
					openFirewall = true;
				};
        coreSite = {
          "fs.defaultFS" = "hdfs://namenode:8020";
          "hadoop.proxyuser.httpfs.groups" = "*";
          "hadoop.proxyuser.httpfs.hosts" = "*";
        };
      };
    };

		
		hiveserver = {...}: {
			imports = [flake.nixosModule];
			environment.systemPackages = with pkgs; [ tmux htop ];
			nix.extraOptions = ''
experimental-features = nix-command flakes
'';
			services.hadoop.hiveserver = {
				enable = true;
				hiveSite = {
					"javax.jdo.option.ConnectionURL" = "jdbc:mysql://localhost/hive?createDatabaseIfNotExist=true";
					"javax.jdo.option.ConnectionDriverName" = "com.mysql.jdbc.Driver";
					"javax.jdo.option.ConnectionUserName" = "hive";
					"javax.jdo.option.ConnectionPassword" = "123456";

					"hive.server2.authentication" = "NOSASL";
          "hive.metastore.uris" = "thrift://hiveserver:9083";

				};
			};

			services.mysql = {
				enable = true;
				package = pkgs.mariadb;
				# ensureUsers = [
				# 	{
				# 		name = "hdfs";
				# 		ensurePermissions ={
				# 			"*.*" = "ALL PRIVILEGES";
				# 		};
				# 	}
				# ];

				initialScript = pkgs.writeText "mysql-init" ''
CREATE USER IF NOT EXISTS 'hive'@'localhost' IDENTIFIED BY '123456';
GRANT ALL PRIVILEGES ON *.* TO 'hive'@'localhost';
'';
			};
			
			services.hadoop = {
				package = pkgs.hadoop;
				coreSite = {
					"fs.defaultFS" = "hdfs://namenode:8020";
					"hadoop.proxyuser.httpfs.groups" = "*";
					"hadoop.proxyuser.httpfs.hosts" = "*";
				};
			};
		};
	};

  testScript = ''

def prime(node, units, ports, test):
    for unit in units:
        node.wait_for_unit(unit)
    for port in ports:
        node.wait_for_open_port(port)
    node.succeed(test)

namenode.start()
datanode.start()
hiveserver.start()

prime(namenode, ["hdfs-namenode", "network.target"], [8020,9870], "curl -f http://namenode:9870")
prime(datanode, ["hdfs-namenode", "network.target"], [9864,9866,9867]"curl -f http://datanode:9864")

# namenode init

namenode.succeed("""
sudo -u hdfs hadoop fs -mkdir -p    /home/hive && \
sudo -u hdfs hadoop fs -chown hive:hadoop    /home/hive  && \
sudo -u hdfs hadoop fs -mkdir       /tmp  && \
sudo -u hdfs hadoop fs -chown hdfs:hadoop   /tmp &&  \
sudo -u hdfs hadoop fs -chmod g+w   /tmp &&  \
sudo -u hdfs hadoop fs -mkdir -p    /user/hive  && \
sudo -u hdfs hadoop fs -chown hive:hadoop   /user/hive &&  \
sudo -u hdfs hadoop fs -mkdir    /user/hive/warehouse  && \
sudo -u hdfs hadoop fs -chmod g+w   /user/hive/warehouse 
""")

hiveserver.execute("schematool -dbType mysql -initSchema -ifNotExists")
hiveserver.wait_for_unit("mysql.service")
hiveserver.wait_for_unit("hiveserver.service")
hiveserver.wait_for_open_port(10000)

hiveserver.succeed(
"beeline -u \"jdbc:hive2://hiveserver:10000/default;auth=noSasl\" -e \"SHOW TABLES;\""
)
  '';
} {
  inherit pkgs;
  inherit (pkgs) system;
}


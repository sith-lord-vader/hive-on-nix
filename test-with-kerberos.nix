{ flake  ? builtins.getFlake (toString ./.)
, pkgs ? flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem}
, makeTest ? pkgs.callPackage (flake.inputs.nixpkgs + "/nixos/tests/make-test-python.nix")
, package ? flake.defaultPackage.${builtins.currentSystem}
}:




makeTest {
  name = "hive";
	nodes = {
		namenode = {pkgs, ...}: {
			imports = [flake.nixosModule];
			services.hive.gatewayRole.enable = true;
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
			services.hive.gatewayRole.enable = true;

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

		kerberos_master = {pkgs,config,...}: {
			nix.extraOptions = ''
experimental-features = nix-command flakes
'';

			krb5 = {
				enable = true;
				realms."HADOOP" = {
					admin_server = "kerberos-master";
					kdc = [ "kerberos-master" ];
				};
				libdefaults.default_realm = "YOG";
			};	
		
			services.kerberos_server = {
				enable = true;
				realms = {
					"HADOOP".acl = [
						{principal = "hdfs/*"; access = "all";}
						{principal = "hiveserver"; access = "all";}
					];
				};
			};

			systemd.services.kadmind.environment.KRB5_KDC_PROFILE = pkgs.lib.mkForce (pkgs.writeText "kdc.conf" ''
${builtins.readFile config.environment.etc."krb5kdc/kdc.conf".source}
	'');
		};

		
		hiveserver = {...}: {
			imports = [flake.nixosModule];
			environment.systemPackages = with pkgs; [ tmux htop ];
			nix.extraOptions = ''
experimental-features = nix-command flakes
'';
			services.hiveserver.enable = true;
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
start_all()

namenode.wait_for_unit("hdfs-namenode")
namenode.wait_for_unit("network.target")
namenode.wait_for_open_port(8020)
namenode.wait_for_open_port(9870)

datanode.wait_for_unit("hdfs-datanode")
datanode.wait_for_unit("network.target")
datanode.wait_for_open_port(9864)
datanode.wait_for_open_port(9866)
datanode.wait_for_open_port(9867)

namenode.succeed("curl -f http://namenode:9870")
datanode.succeed("curl -f http://datanode:9864")

datanode.succeed("sudo -u hdfs hdfs dfsadmin -safemode wait")
datanode.succeed("echo testfilecontents | sudo -u hdfs hdfs dfs -put - /testfile")
assert "testfilecontents" in datanode.succeed("sudo -u hdfs hdfs dfs -cat /testfile")

namenode.wait_for_unit("hdfs-httpfs")
namenode.wait_for_open_port(14000)
# assert "testfilecontents" in datanode.succeed("curl -f \"http://namenode:14000/webhdfs/v1/testfile?user.name=hdfs&op=OPEN\" 2>&1")

hiveserver.wait_for_unit("hiveserver.service")
hiveserver.succeed(
"echo \"hello\" "
)
hiveserver.execute(
"beeline -u jdbc:hive2://hiveserver:10000 -e \"SHOW TABLES\""
)
  '';
} {
  inherit pkgs;
  inherit (pkgs) system;
}


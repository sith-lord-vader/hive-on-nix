{ flake  ? builtins.getFlake (toString ./.)
, pkgs ? flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem}
, makeTest ? pkgs.callPackage (flake.inputs.nixpkgs + "/nixos/tests/make-test-python.nix")
, package ? flake.defaultPackage.${builtins.currentSystem}
}:



let

	krb5 = {
		enable = true;
		realms."TEST.REALM" = {
			admin_server = "kerb";
			kdc = [ "kerb" ];
		};
		libdefaults.default_realm = "TEST.REALM";
	};
	
	package = pkgs.hadoop;
	coreSite = {
    "fs.defaultFS" = "hdfs://ns1";
		# # Kerberos
		"hadoop.security.authentication" = "kerberos";
		"hadoop.security.authorization" = "true";
		"hadoop.rpc.protection" = "authentication";
		# "hadoop.security.auth_to_local" = config.environment.etc."krb5.conf".text; # uncomment only after we've figured out auth_to_local rewrite rule additions to krb5.conf
  };
	
	hdfsSite = {
    # HA Quorum Journal Manager configuration
    "dfs.nameservices" = "ns1";
    "dfs.ha.namenodes.ns1" = "nn1,nn2";
    "dfs.namenode.shared.edits.dir.ns1" = "qjournal://jn1:8485/ns1";
    "dfs.namenode.rpc-address.ns1.nn1" = "nn1:8020";
    "dfs.namenode.rpc-address.ns1.nn2" = "nn2:8020";
    "dfs.namenode.servicerpc-address.ns1.nn1" = "nn1:8022";
    "dfs.namenode.servicerpc-address.ns1.nn2" = "nn2:8022";
    "dfs.namenode.http-address.ns1.nn1" = "nn1:9870";
    "dfs.namenode.http-address.ns1.nn2" = "nn2:9870";
    # Automatic failover configuration
    "dfs.client.failover.proxy.provider.ns1" = "org.apache.hadoop.hdfs.server.namenode.ha.ConfiguredFailoverProxyProvider";
    "dfs.ha.automatic-failover.enabled.ns1" = "true";
    "dfs.ha.fencing.methods" = "shell(true)";
    "ha.zookeeper.quorum" = "zk:2181";


		# kerberos
		"dfs.block.access.token.enable" = "true";
		"dfs.namenode.kerberos.principal" = "hdfs/_HOST@TEST.REALM";
		"dfs.namenode.keytab.file" = "/var/security/keytab/nn.service.keytab";

		"dfs.journalnode.kerberos.principal" = "hdfs/_HOST@TEST.REALM";
		"dfs.journalnode.keytab.file" = "/var/security/keytab/jn.service.keytab";

		"dfs.datanode.data.dir.perm" = "700";
		"dfs.datanode.kerberos.principal" = "hdfs/_HOST@TEST.REALM";
		"dfs.datanode.keytab.file" = "/var/security/keytab/dn.service.keytab";

		# SASL based secure datanode
		"dfs.http.policy" = "HTTPS_ONLY";
		"dfs.data.transfer.protection" = "authentication";
		
		# # webui configs
		# "dfs.namenode.kerberos.internal.spnego.principal" = "HTTP/_HOST/TEST.REALM";
		# "dfs.web.authentication.kerberos.keytab" = "/var/security/keytab/nn.service.keytab";
		# "dfs.journalnode.kerberos.internal.spnego.principal" = "HTTP/_HOST/TEST.REALM";
		# "dfs.journalnode.https-address" = "0.0.0.0:8481";

		
	};

in

makeTest {
  name = "hive-with-kerberos";
	nodes = {

		zk = { ... }: {
			inherit krb5;
      services.zookeeper.enable = true;
      networking.firewall.allowedTCPPorts = [ 2181 ];
    };

		nn1 = {pkgs, ...}: {
			imports = [flake.nixosModule];
			inherit krb5;
			services.hadoop.hiveserver.gatewayRole.enable = true;

      services.hadoop = {
				inherit package coreSite hdfsSite;
        hdfs = {
          namenode = {
            enable = true;
						openFirewall = true;
          };
        };
				hdfs.zkfc.enable = true;
      };
    };

		nn2 = {pkgs, ...}: {
			imports = [flake.nixosModule];
			inherit krb5;
			services.hadoop.hiveserver.gatewayRole.enable = true;

      services.hadoop = {
				inherit package coreSite hdfsSite;
        hdfs = {
          namenode = {
            enable = true;
            formatOnInit = true;
						openFirewall = true;
          };
        };
				hdfs.zkfc.enable = true;
      };
    };
		
    jn1 = { ... }: {
			inherit krb5;
      services.hadoop = {
        inherit package coreSite hdfsSite;
        hdfs.journalnode = {
          enable = true;
          openFirewall = true;
        };
      };
    };

		dn1 = {pkgs, ...}: {
			imports = [flake.nixosModule];
			inherit krb5;
      services.hadoop = {
				inherit package coreSite hdfsSite;
				hiveserver.gatewayRole.enable = true;
        hdfs.datanode = {
					enable = true;
					openFirewall = true;
				};
      };
    };

		kerb = {pkgs,config,...}: {
			nix.extraOptions = ''
experimental-features = nix-command flakes
'';

			inherit krb5;
			
			services.kerberos_server = {
				enable = true;
				realms = {
					"TEST.REALM".acl = [
						{principal = "zookeeper/*"; access = "all";}
						{principal = "hdfs/*"; access = "all";}
						{principal = "hiveserver"; access = "all";}
					];
				};				
			};

			networking.firewall.allowedTCPPorts = [ 88 464 749 ];
			networking.firewall.allowedUDPPorts = [ 88 464 ];
			systemd.services.kadmind.environment.KRB5_KDC_PROFILE = pkgs.lib.mkForce (pkgs.writeText "kdc.conf" ''
${builtins.readFile config.environment.etc."krb5kdc/kdc.conf".source}
	'');
		};

		
		hiveserver = {...}: {
			imports = [flake.nixosModule];
			inherit krb5;

			environment.systemPackages = with pkgs; [ tmux htop ];
			nix.extraOptions = ''
experimental-features = nix-command flakes
'';
			services.hadoop = {
				inherit package coreSite hdfsSite;
				
				hiveserver = {
					enable = true;
					openFirewall = true;

					hiveSite = {
						"javax.jdo.option.ConnectionURL" = "jdbc:mysql://localhost/hive?createDatabaseIfNotExist=true";
						"javax.jdo.option.ConnectionDriverName" = "com.mysql.jdbc.Driver";
						"javax.jdo.option.ConnectionUserName" = "hive";
						"javax.jdo.option.ConnectionPassword" = "123456";

					};
				};
			};

			services.mysql = {
				enable = true;
				package = pkgs.mariadb;

				initialScript = pkgs.writeText "mysql-init" ''
CREATE USER IF NOT EXISTS 'hive'@'localhost' IDENTIFIED BY '123456';
GRANT ALL PRIVILEGES ON *.* TO 'hive'@'localhost';
'';
			};			
		};
	};

  testScript = ''

kerb.start()
zk.start()
nn1.start()
nn2.start()
jn1.start()
dn1.start()
hiveserver.start()


kerb.succeed("kdb5_util create -r \"TEST.REALM\" -P qwe -s")
kerb.systemctl("restart kadmind.service kdc.service")
kerb.wait_for_unit("kadmind.service")
kerb.succeed("kadmin.local -q \"addprinc -pw abc zookeeper/zk\"")
kerb.succeed("kadmin.local -q \"addprinc -pw abc hdfs/nn1\"")
kerb.succeed("kadmin.local -q \"addprinc -pw abc hdfs/nn2\"")
kerb.succeed("kadmin.local -q \"addprinc -pw abc hdfs/jn1\"")
kerb.succeed("kadmin.local -q \"addprinc -pw abc hdfs/dn1\"")
kerb.succeed("kadmin.local -q \"addprinc -pw abc hiveserver\"")


kerb.wait_for_unit("network.target")
zk.wait_for_unit("network.target")
jn1.wait_for_unit("network.target")
nn1.wait_for_unit("network.target")
dn1.wait_for_unit("network.target")
hiveserver.wait_for_unit("network.target")


zk.succeed("mkdir -p /var/security/keytab/")

zk.succeed("kadmin -p zookeeper/zk -w \"abc\" -q \"ktadd -k /var/security/keytab/zk.service.keytab zookeeper/zk\"")
zk.succeed("chown zookeeper:zookeeper /var/security/keytab/zk.service.keytab")

nn1.succeed("mkdir -p /var/security/keytab/")
nn1.succeed("kadmin -p hdfs/nn1 -w \"abc\" -q \"ktadd -k /var/security/keytab/nn.service.keytab hdfs/nn1\"")
nn1.succeed("chown hdfs /var/security/keytab/nn.service.keytab")
nn1.succeed("chgrp hadoop /var/security/keytab/nn.service.keytab")

nn2.succeed("mkdir -p /var/security/keytab/")
nn2.succeed("kadmin -p hdfs/nn2 -w \"abc\" -q \"ktadd -k /var/security/keytab/nn.service.keytab hdfs/nn2\"")
nn2.succeed("chown hdfs /var/security/keytab/nn.service.keytab")
nn2.succeed("chgrp hadoop /var/security/keytab/nn.service.keytab")

jn1.succeed("mkdir -p /var/security/keytab/")
jn1.succeed("kadmin -p hdfs/jn1 -w \"abc\" -q \"ktadd -k /var/security/keytab/jn.service.keytab hdfs/jn1\"")
jn1.succeed("chown hdfs /var/security/keytab/jn.service.keytab")
jn1.succeed("chgrp hadoop /var/security/keytab/jn.service.keytab")

dn1.succeed("mkdir -p /var/security/keytab/")
dn1.succeed("kadmin -p hdfs/dn1 -w \"abc\" -q \"ktadd -k /var/security/keytab/dn.service.keytab hdfs/dn1\"")
dn1.succeed("chown hdfs /var/security/keytab/dn.service.keytab")
dn1.succeed("chgrp hadoop /var/security/keytab/dn.service.keytab")

hiveserver.succeed("mkdir -p /var/security/keytab/")
hiveserver.succeed("kadmin -p hiveserver -w \"abc\" -q \"ktadd -k /var/security/keytab/hiveserver.service.keytab hiveserver\"")
hiveserver.succeed("chown hive /var/security/keytab/hiveserver.service.keytab")
hiveserver.succeed("chgrp hadoop /var/security/keytab/hiveserver.service.keytab")

zk.wait_for_unit("zookeeper")
zk.wait_for_unit("zookeeper")

zk.wait_for_open_port(2181)
jn1.wait_for_open_port(8480)
jn1.wait_for_open_port(8485)

# Namenodes must be stopped before initializing the cluster
nn1.succeed("systemctl stop hdfs-namenode")
nn2.succeed("systemctl stop hdfs-namenode")
nn1.succeed("systemctl stop hdfs-zkfc")
nn2.succeed("systemctl stop hdfs-zkfc")

# Initialize zookeeper for failover controller
nn1.succeed("sudo -u hdfs hdfs zkfc -formatZK 2>&1 | systemd-cat")

# Format NN1 and start it
nn1.succeed("sudo -u hdfs hadoop namenode -format 2>&1 | systemd-cat")
nn1.succeed("systemctl start hdfs-namenode")
nn1.wait_for_open_port(9870)
nn1.wait_for_open_port(8022)
nn1.wait_for_open_port(8020)

# Bootstrap NN2 from NN1 and start it
nn2.succeed("sudo -u hdfs hdfs namenode -bootstrapStandby 2>&1 | systemd-cat")
nn2.succeed("systemctl start hdfs-namenode")
nn2.wait_for_open_port(9870)
nn2.wait_for_open_port(8022)
nn2.wait_for_open_port(8020)
nn1.succeed("netstat -tulpne | systemd-cat")

# Start failover controllers
nn1.succeed("systemctl start hdfs-zkfc")
nn2.succeed("systemctl start hdfs-zkfc")

# DN should have started by now, but confirm anyway
dn1.wait_for_unit("hdfs-datanode")
dn1.succeed("netstat -tulpne | systemd-cat")


# Print states of namenodes
hiveserver.succeed("sudo -u hdfs hdfs haadmin -getAllServiceState | systemd-cat")
# Wait for cluster to exit safemode
hiveserver.succeed("sudo -u hdfs hdfs dfsadmin -safemode wait")
hiveserver.succeed("sudo -u hdfs hdfs haadmin -getAllServiceState | systemd-cat")
# test R/W
hiveserver.succeed("echo testfilecontents | sudo -u hdfs hdfs dfs -put - /testfile")
assert "testfilecontents" in hiveserver.succeed("sudo -u hdfs hdfs dfs -cat /testfile")



nn1.succeed("curl -f http://nn1:9870")
dn1.succeed("curl -f https://dn1:9865")


hiveserver.wait_for_unit("mysql.service")
hiveserver.succeed("systemctl restart hive-init")
hiveserver.succeed("systemctl restart hiveserver")
hiveserver.wait_for_open_port(10000)
hiveserver.execute(
"beeline -u jdbc:hive2://hiveserver:10000 -e \"SHOW TABLES;\""
)
  '';
} {
  inherit pkgs;
  inherit (pkgs) system;
}


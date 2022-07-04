{ flake  ? builtins.getFlake (toString ./.)
, pkgs ? flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem}
, makeTest ? pkgs.callPackage (flake.inputs.nixpkgs + "/nixos/tests/make-test-python.nix")
, package ? flake.defaultPackage.${builtins.currentSystem}
}:



let
	tmpFileRules = ["d /var/hadoop 0755 hdfs hadoop"];

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

		"hadoop.tmp.dir" = "/var/hadoop";
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
    "dfs.namenode.https-address.ns1.nn1" = "nn1:9871";
    "dfs.namenode.https-address.ns1.nn2" = "nn2:9871";
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

		"fs.checkpoint.dir" = "/var/hadoop";
		"dfs.name.dir" = "/var/hadoop";
		"dfs.data.dir" = "/var/hadoop";
		
		# "dfs.datanode.data.dir.perm" = "700";
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
	jaasConf = service: princ:  pkgs.writeTextFile {
		name = "jaas.conf";
		text = ''
Server {
com.sun.security.auth.module.Krb5LoginModule required
useKeyTab=true
keyTab="/var/security/keytab/${service}.service.keytab"
storeKey=true
useTicketCache=false
principal="${princ}@TEST.REALM";
};
'';
	};
	authFlag = service: princ: [ "-Djava.security.auth.login.config=${jaasConf service princ}" ];
in

makeTest {
  name = "hive-with-kerberos";
	nodes = {

		zk = { ... }: {
			inherit krb5;
      services.zookeeper = {
				enable = true;
				# extraConf = ''
				# authProvider.1=org.apache.zookeeper.auth.SASLAuthenticationProvider
				# jaasLoginRenew=3600000
				# '';
				# extraCmdLineOptions = authFlag "zookeeper" "zookeeper/zk";
			};
      networking.firewall.allowedTCPPorts = [ 2181 ];
    };

		nn1 = {pkgs, ...}: {
			imports = [flake.nixosModule];
			inherit krb5;
			services.hadoop.hiveserver.gatewayRole.enable = true;

			systemd.tmpfiles.rules = tmpFileRules;
      services.hadoop = {
				inherit package coreSite hdfsSite;
        hdfs = {
          namenode = {
						# extraFlags = authFlag "nn" "hdfs/nn1";
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

			systemd.tmpfiles.rules = tmpFileRules;
      services.hadoop = {
				inherit package coreSite hdfsSite;
        hdfs = {
          namenode = {
						# extraFlags = authFlag "nn" "hdfs/nn2";
            enable = true;
						openFirewall = true;
          };
        };
				hdfs.zkfc.enable = true;
      };
    };
		
    jn1 = { ... }: {
			inherit krb5;

      systemd.tmpfiles.rules = tmpFileRules;
			services.hadoop = {
        inherit package coreSite hdfsSite;
        hdfs.journalnode = {
					# extraFlags = authFlag "jn" "hdfs/jn1";
          enable = true;
          openFirewall = true;
        };
      };
    };

		dn1 = {pkgs, ...}: {
			imports = [flake.nixosModule];
			inherit krb5;

			systemd.tmpfiles.rules = tmpFileRules;
      services.hadoop = {
				inherit package coreSite hdfsSite;
				hiveserver.gatewayRole.enable = true;
        hdfs.datanode = {
					# extraFlags = authFlag "dn" "hdfs/dn1";
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
kerb.succeed("kdb5_util create -r \"TEST.REALM\" -P qwe -s")
kerb.systemctl("restart kadmind.service kdc.service")
kerb.wait_for_unit("kadmind.service")
kerb.succeed("kadmin.local -q \"addprinc -pw abc zookeeper/zk\"")
kerb.succeed("kadmin.local -q \"addprinc -pw abc hdfs/nn1\"")
kerb.succeed("kadmin.local -q \"addprinc -pw abc hdfs/nn2\"")
kerb.succeed("kadmin.local -q \"addprinc -pw abc hdfs/jn1\"")
kerb.succeed("kadmin.local -q \"addprinc -pw abc hdfs/dn1\"")
kerb.succeed("kadmin.local -q \"addprinc -pw abc hiveserver\"")


zk.start()
nn1.start()
jn1.start()
# hiveserver.start()

kerb.wait_for_unit("network.target")
zk.wait_for_unit("network.target")
jn1.wait_for_unit("network.target")
nn1.wait_for_unit("network.target")


nn1.succeed("mkdir -p /var/security/keytab/")
nn1.succeed("kadmin -p hdfs/nn1 -w \"abc\" -q \"ktadd -k /var/security/keytab/nn.service.keytab hdfs/nn1\"")
nn1.succeed("chown hdfs /var/security/keytab/nn.service.keytab")
nn1.succeed("chgrp hadoop /var/security/keytab/nn.service.keytab")

zk.succeed("mkdir -p /var/security/keytab/")
zk.succeed("kadmin -p zookeeper/zk -w \"abc\" -q \"ktadd -k /var/security/keytab/zookeeper.service.keytab zookeeper/zk\"")
zk.succeed("chown zookeeper:zookeeper /var/security/keytab/zookeeper.service.keytab")

jn1.succeed("mkdir -p /var/security/keytab/")
jn1.succeed("kadmin -p hdfs/jn1 -w \"abc\" -q \"ktadd -k /var/security/keytab/jn.service.keytab hdfs/jn1\"")
jn1.succeed("chown hdfs /var/security/keytab/jn.service.keytab")
jn1.succeed("chgrp hadoop /var/security/keytab/jn.service.keytab")

zk.wait_for_unit("zookeeper")
zk.wait_for_unit("zookeeper")

zk.wait_for_open_port(2181)
jn1.wait_for_open_port(8481)
jn1.wait_for_open_port(8485)

# Namenodes must be stopped before initializing the cluster
nn1.succeed("systemctl stop hdfs-namenode")
nn1.succeed("systemctl stop hdfs-zkfc")

# Initialize zookeeper for failover controller
nn1.succeed("kinit -k -t /var/security/keytab/nn.service.keytab hdfs/nn1")
nn1.succeed("hdfs zkfc -formatZK 2>&1 | systemd-cat")

# Format NN1 and start it
nn1.succeed("hadoop namenode -format 2>&1 | systemd-cat")

nn1.wait_for_unit("hdfs-namenode.service")
nn1.wait_for_open_port(9871)
nn1.wait_for_open_port(8022)
nn1.wait_for_open_port(8020)


nn2.start()
nn2.succeed("systemctl stop hdfs-zkfc")
nn2.succeed("systemctl stop hdfs-namenode")

nn2.succeed("mkdir -p /var/security/keytab/")
nn2.succeed("kadmin -p hdfs/nn2 -w \"abc\" -q \"ktadd -k /var/security/keytab/nn.service.keytab hdfs/nn2\"")
nn2.succeed("chown hdfs /var/security/keytab/nn.service.keytab")
nn2.succeed("chgrp hadoop /var/security/keytab/nn.service.keytab")


# Bootstrap NN2 from NN1 and start it
nn2.succeed("kinit -k -t /var/security/keytab/nn.service.keytab hdfs/nn2")
nn2.succeed("hdfs namenode -bootstrapStandby 2>&1 | systemd-cat")
nn2.succeed("systemctl start hdfs-namenode")
nn2.wait_for_open_port(9871)
nn2.wait_for_open_port(8022)
nn2.wait_for_open_port(8020)
nn1.succeed("netstat -tulpne | systemd-cat")

# Start failover controllers
nn1.succeed("systemctl start hdfs-zkfc")
nn2.succeed("systemctl start hdfs-zkfc")

# DN 
dn1.start()
dn1.wait_for_unit("network.target")
dn1.succeed("mkdir -p /var/security/keytab/")
dn1.succeed("kadmin -p hdfs/dn1 -w \"abc\" -q \"ktadd -k /var/security/keytab/dn.service.keytab hdfs/dn1\"")
dn1.succeed("chown hdfs /var/security/keytab/dn.service.keytab")
dn1.succeed("chgrp hadoop /var/security/keytab/dn.service.keytab")

dn1.wait_for_unit("hdfs-datanode")
dn1.succeed("netstat -tulpne | systemd-cat")

nn1.succeed("curl -f https://nn1:9871")
dn1.succeed("curl -f https://dn1:9865")


# hiveserver.wait_for_unit("network.target")
# hiveserver.succeed("mkdir -p /var/security/keytab/")
# hiveserver.succeed("kadmin -p hiveserver -w \"abc\" -q \"ktadd -k /var/security/keytab/hiveserver.service.keytab hiveserver\"")
# hiveserver.succeed("chown hive /var/security/keytab/hiveserver.service.keytab")
# hiveserver.succeed("chgrp hadoop /var/security/keytab/hiveserver.service.keytab")


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


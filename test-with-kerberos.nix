{ flake  ? builtins.getFlake (toString ./.)
, pkgs ? flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem}
, makeTest ? pkgs.callPackage (flake.inputs.nixpkgs + "/nixos/tests/make-test-python.nix")
, package ? flake.defaultPackage.${builtins.currentSystem}
}:


with pkgs;
with lib;

let
	tmpFileRules = ["d /var/security/keytab 0755 root users" "d /var/hadoop 0777 hdfs hadoop"];

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

		
		# "hadoop.ssl.require.client.cert" = "false";
		# "hadoop.ssl.hostname.verifier" = "DEFAULT";
		# "hadoop.ssl.keystores.factory.class" = "org.apache.hadoop.security.ssl.FileBasedKeyStoresFactory";
  };

	sslServer = {
		"ssl.server.truststore.location" = "${./minica/jssecacerts}";
		"ssl.server.truststore.password" = "changeit";
		"ssl.server.truststore.type" = "jks";
		"ssl.server.keystore.location" = "/var/security/keystore.jks";
		"ssl.server.keystore.password" = "changeit";
		"ssl.server.keystore.type" = "jks";
	};

	sslClient = {
		"ssl.client.truststore.location" = "${./minica/jssecacerts}";
		"ssl.client.truststore.password" = "changeit";
		"ssl.client.truststore.type" = "jks";
		"ssl.client.keystore.location" = "/var/security/keystore.jks";
		"ssl.client.keystore.password" = "changeit";
		"ssl.client.keystore.type" = "jks";
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
		# "dfs.client.https.need-auth" = "false";

		"dfs.data.transfer.protection" = "authentication";


		# # webui configs
		# "dfs.namenode.kerberos.internal.spnego.principal" = "HTTP/_HOST/TEST.REALM";
		# "dfs.web.authentication.kerberos.keytab" = "/var/security/keytab/nn.service.keytab";
		# "dfs.journalnode.kerberos.internal.spnego.principal" = "HTTP/_HOST/TEST.REALM";
		# "dfs.journalnode.https-address" = "0.0.0.0:8481";

		
	};

	yarnSite = {
    "yarn.resourcemanager.zk-address" = "zk:2181";
    "yarn.resourcemanager.ha.enabled" = "false";
    # "yarn.resourcemanager.ha.rm-ids" = "rm1";
    "yarn.resourcemanager.hostname" = "rm1";
    # "yarn.resourcemanager.ha.automatic-failover.enabled" = "true";
    # "yarn.resourcemanager.cluster-id" = "cluster1";
    # yarn.resourcemanager.webapp.address needs to be defined even though yarn.resourcemanager.hostname is set. This shouldn't be necessary, but there's a bug in
    # hadoop-yarn-project/hadoop-yarn/hadoop-yarn-server/hadoop-yarn-server-web-proxy/src/main/java/org/apache/hadoop/yarn/server/webproxy/amfilter/AmFilterInitializer.java:70
    # that causes AM containers to fail otherwise.
    "yarn.resourcemanager.webapp.address" = "rm1:8088";
    "yarn.resourcemanager.webapp.https.address" = "rm1:8090";
		"yarn.resourcemanager.principal" = "yarn/_HOST@TEST.REALM";
		"yarn.resourcemanager.keytab" = "/var/security/keytab/rm.service.keytab";

		"yarn.nodemanager.principal" = "yarn/_HOST@TEST.REALM";
		"yarn.nodemanager.keytab" = "/var/security/keytab/nm.service.keytab";
    "yarn.resourcemanager.scheduler.class" = "org.apache.hadoop.yarn.server.resourcemanager.scheduler.fair.FairScheduler";
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
			systemd.tmpfiles.rules = tmpFileRules;
			networking.hosts = {
				"127.0.0.2" = lib.mkForce [ ];
				"::1" = lib.mkForce [ ]; 
			};
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
			imports = [flake.nixosModules.hiveserver];
			inherit krb5;
			services.hadoop.hiveserver.gatewayRole.enable = true;
			networking.hosts = {
				"127.0.0.2" = lib.mkForce [ ];
				"::1" = lib.mkForce [ ]; 
			};

			systemd.tmpfiles.rules = tmpFileRules;
      services.hadoop = {
				inherit package coreSite hdfsSite sslServer sslClient;
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
			networking.hosts = {
				"127.0.0.2" = lib.mkForce [ ];
				"::1" = lib.mkForce [ ]; 
			};

			systemd.tmpfiles.rules = tmpFileRules;
      services.hadoop = {
				inherit package coreSite hdfsSite sslServer sslClient;
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
			networking.hosts = {
				"127.0.0.2" = lib.mkForce [ ];
				"::1" = lib.mkForce [ ]; 
			};

			services.hadoop = {
        inherit package coreSite hdfsSite sslServer sslClient;
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
     	networking.hosts = {
				"127.0.0.2" = lib.mkForce [ ];
				"::1" = lib.mkForce [ ]; 
			};

			services.hadoop = {
				inherit package coreSite hdfsSite sslServer sslClient;
				hiveserver.gatewayRole.enable = true;
        hdfs.datanode = {
					# extraFlags = authFlag "dn" "hdfs/dn1";
					enable = true;
					openFirewall = true;
				};
      };
    };

    # YARN cluster
    rm1 = { config,options, ... }: {
			imports = [flake.nixosModule];
			inherit krb5;

			systemd.tmpfiles.rules =  ["d /var/security/keytab 0755 root users" "d /var/hadoop 0777 yarn hadoop"];
     	networking.hosts = {
				"127.0.0.2" = lib.mkForce [ ];
				"::1" = lib.mkForce [ ]; 
			};

      services.hadoop = {
        inherit package coreSite hdfsSite yarnSite sslServer sslClient;
        yarn.resourcemanager = {
          enable = true;
          openFirewall = true;
        };
      };
			networking.firewall.allowedTCPPorts = [ 8090 ];
    };

    nm1 = { config, options, ... }: {
			imports = [flake.nixosModule];
			inherit krb5;

			systemd.tmpfiles.rules =  ["d /var/security/keytab 0755 root users" "d /var/hadoop 0777 yarn hadoop"];
     	networking.hosts = {
				"127.0.0.2" = lib.mkForce [ ];
				"::1" = lib.mkForce [ ]; 
			};
      virtualisation.memorySize = 2048;
      services.hadoop = {
        inherit package coreSite hdfsSite yarnSite sslServer sslClient;
        yarn.nodemanager = {
          enable = true;
          openFirewall = true;
        };
      };
			networking.firewall.allowedTCPPorts = [ 8044 ];
    };

		
		kerb = {pkgs,config,...}: {
			nix.extraOptions = ''
experimental-features = nix-command flakes
'';

			inherit krb5;
			networking.hosts = {
				"127.0.0.2" = lib.mkForce [ ];
				"::1" = lib.mkForce [ ]; 
			};
			systemd.tmpfiles.rules = tmpFileRules;	
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
			
			networking.hosts = {
				"127.0.0.2" = lib.mkForce [ ];
				"::1" = lib.mkForce [ ]; 
			};
			systemd.tmpfiles.rules = tmpFileRules;
			environment.systemPackages = with pkgs; [ tmux htop ];
			nix.extraOptions = ''
experimental-features = nix-command flakes
'';
			services.hadoop = {
				inherit package coreSite hdfsSite yarnSite sslServer sslClient;
				gatewayRole.enable = true;
				hiveserver = {
					enable = true;
					openFirewall = true;

					hiveSite = {
						"javax.jdo.option.ConnectionURL" = "jdbc:mysql://localhost/hive?createDatabaseIfNotExist=true";
						"javax.jdo.option.ConnectionDriverName" = "com.mysql.jdbc.Driver";
						"javax.jdo.option.ConnectionUserName" = "hive";
						"javax.jdo.option.ConnectionPassword" = "123456";

						"hive.server2.authentication" = "KERBEROS";
						"hive.server2.authentication.kerberos.principal" = "hive/hiveserver";
						"hive.server2.authentication.kerberos.keytab" = "/var/security/keytab/hiveserver.service.keytab";

						# "hive.server2.use.SSL" = "true";
						# "hive.server2.keystore.path" = "/var/security/keystore.jks";
						# "hive.server2.keystore.password" = "changeit";
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

start_all()



kerb.succeed("kdb5_util create -r \"TEST.REALM\" -P qwe -s")
kerb.systemctl("restart kadmind.service kdc.service")
kerb.wait_for_unit("kadmind.service")

zk_nodes =  [zk ]
nn_nodes = [ nn1 nn2  ]
jn_nodes = [jn1]
dn_nodes = [dn1 dn2]
yarn_nodes = [ rm1 nm1]
hive_nodes = [hiveserver]
all_nodes = zk_nodes ++ nn_nodes ++ jn_nodes ++dn_nodes ++ yarn_nodes ++ hiveserver


kerb.succeed("kadmin.local -q \"addprinc -pw abc zookeeper/zk\"")
kerb.succeed("kadmin.local -q \"addprinc -pw abc hdfs/nn1\"")
kerb.succeed("kadmin.local -q \"addprinc -pw abc hdfs/nn2\"")
kerb.succeed("kadmin.local -q \"addprinc -pw abc hdfs/jn1\"")
kerb.succeed("kadmin.local -q \"addprinc -pw abc hdfs/dn1\"")
kerb.succeed("kadmin.local -q \"addprinc -pw abc yarn/rm1\"")
kerb.succeed("kadmin.local -q \"addprinc -pw abc yarn/nm1\"")
kerb.succeed("kadmin.local -q \"addprinc -pw abc hive/hiveserver\"")


kerb.wait_for_unit("network.target")
zk.wait_for_unit("network.target")
jn1.wait_for_unit("network.target")
nn1.wait_for_unit("network.target")
dn1.wait_for_unit("network.target")


# TODO finish this
def cert_init(node,node_type,principal,user):
    node.succeed("kadmin -p "+principal+" -w \"abc\" -q \"ktadd -k /var/security/keytab/"+node_type+".service.keytab "+principal+"\"")
    node.copy_from_host(source="${./minica/nn1/keystore.jks}",target="/var/security/keystore.jks")
    node.succeed("chown -R "+user+" /var/security")



nn1.succeed("kadmin -p hdfs/nn1 -w \"abc\" -q \"ktadd -k /var/security/keytab/nn.service.keytab hdfs/nn1\"")
nn1.copy_from_host(source="${./minica/nn1/keystore.jks}",target="/var/security/keystore.jks")
# nn1.copy_from_host(source="${./minica/jssecacerts}",target="/var/security/jssecacerts")
nn1.succeed("chown -R hdfs /var/security")
nn1.succeed("chgrp -R hadoop /var/security")

nn2.succeed("kadmin -p hdfs/nn2 -w \"abc\" -q \"ktadd -k /var/security/keytab/nn.service.keytab hdfs/nn2\"")
nn2.copy_from_host(source="${./minica/nn2/keystore.jks}",target="/var/security/keystore.jks")
# nn2.copy_from_host(source="${./minica/jssecacerts}",target="/var/security/jssecacerts")
nn2.succeed("chown -R hdfs /var/security")
nn2.succeed("chgrp -R hadoop /var/security")

zk.succeed("kadmin -p zookeeper/zk -w \"abc\" -q \"ktadd -k /var/security/keytab/zookeeper.service.keytab zookeeper/zk\"")
zk.copy_from_host(source="${./minica/zk/keystore.jks}",target="/var/security/keystore.jks")
# zk.copy_from_host(source="${./minica/jssecacerts}",target="/var/security/jssecacerts")
zk.succeed("chown -R zookeeper /var/security")
zk.succeed("chgrp -R zookeeper /var/security")

jn1.succeed("kadmin -p hdfs/jn1 -w \"abc\" -q \"ktadd -k /var/security/keytab/jn.service.keytab hdfs/jn1\"")
jn1.copy_from_host(source="${./minica/jn1/keystore.jks}",target="/var/security/keystore.jks")
# jn1.copy_from_host(source="${./minica/jssecacerts}",target="/var/security/jssecacerts")
jn1.succeed("chown -R hdfs /var/security")
jn1.succeed("chgrp -R hadoop /var/security")

dn1.succeed("kadmin -p hdfs/dn1 -w \"abc\" -q \"ktadd -k /var/security/keytab/dn.service.keytab hdfs/dn1\"")
dn1.copy_from_host(source="${./minica/dn1/keystore.jks}",target="/var/security/keystore.jks")
# dn1.copy_from_host(source="${./minica/jssecacerts}",target="/var/security/jssecacerts")
dn1.succeed("chown -R hdfs /var/security")
dn1.succeed("chgrp -R hadoop /var/security")


rm1.succeed("kadmin -p yarn/rm1 -w \"abc\" -q \"ktadd -k /var/security/keytab/rm.service.keytab yarn/rm1\"")
rm1.copy_from_host(source="${./minica/rm1/keystore.jks}",target="/var/security/keystore.jks")
# rm1.copy_from_host(source="${./minica/jssecacerts}",target="/var/security/jssecacerts")
rm1.succeed("chown -R yarn /var/security")
rm1.succeed("chgrp -R hadoop /var/security")

nm1.succeed("kadmin -p yarn/nm1 -w \"abc\" -q \"ktadd -k /var/security/keytab/nm.service.keytab yarn/nm1\"")
nm1.copy_from_host(source="${./minica/nm1/keystore.jks}",target="/var/security/keystore.jks")
# nm1.copy_from_host(source="${./minica/jssecacerts}",target="/var/security/jssecacerts")
nm1.succeed("chown -R yarn /var/security")
nm1.succeed("chgrp -R hadoop /var/security")


zk.wait_for_unit("zookeeper")
zk.wait_for_open_port(2181)


jn1.wait_for_unit("hdfs-journalnode")
jn1.wait_for_open_port(8481) # one jn might be problem
jn1.wait_for_open_port(8485)



# Namenodes must be stopped before initializing the cluster
[nn.succeed("systemctl stop hdfs-namenode") for nn in nn_nodes]
[nn.succeed("systemctl stop hdfs-zkfc") for nn in nn_nodes]

# Initialize zookeeper for failover controller
nn1.succeed("kinit -k -t /var/security/keytab/nn.service.keytab hdfs/nn1")
nn1.succeed("hdfs zkfc -formatZK 2>&1 | systemd-cat")

# Format NN1 and start it
nn1.succeed("hadoop namenode -format -nonInteractive 2>&1 | systemd-cat")
nn1.succeed("chown -R hdfs /var/hadoop")
nn1.succeed("chgrp -R hadoop /var/hadoop")

nn1.succeed("systemctl start hdfs-namenode.service")
nn1.wait_for_open_port(8022)
nn1.wait_for_open_port(8020)


# Bootstrap NN2 from NN1 and start it
nn2.succeed("hdfs namenode -bootstrapStandby 2>&1 | systemd-cat")
nn2.succeed("chown -R hdfs /var/hadoop")
nn2.succeed("chgrp -R hadoop /var/hadoop")
nn2.succeed("systemctl start hdfs-namenode")
nn2.wait_for_open_port(8022)
nn2.wait_for_open_port(8020)


nn1.succeed("netstat -tulpne | systemd-cat")

# Start failover controllers
[nn.succeed("systemctl start hdfs-zkfc") for nn in nn_nodes]

# DN 
dn1.wait_for_unit("hdfs-datanode")
dn1.succeed("netstat -tulpne | systemd-cat")

nn1.succeed("curl --cacert ${./minica/minica.pem} -f https://nn1:9871")
dn1.succeed("curl --cacert ${./minica/minica.pem} -f https://dn1:9865")


[n.wait_for_unit("network.target") for n in yarn_nodes]

rm1.wait_for_unit("yarn-resourcemanager")
nm1.wait_for_unit("yarn-nodemanager")

nm1.succeed("kinit -k -t /var/security/keytab/nm.service.keytab yarn/nm1")
nm1.wait_until_succeeds("yarn node -list | grep Nodes:1")
nm1.succeed("yarn node -list | systemd-cat")




hiveserver.wait_for_unit("network.target")
hiveserver.succeed("kadmin -p hive/hiveserver -w \"abc\" -q \"ktadd -k /var/security/keytab/hiveserver.service.keytab hive/hiveserver\"")
hiveserver.succeed("chown hive /var/security/keytab/hiveserver.service.keytab")
hiveserver.succeed("chgrp hadoop /var/security/keytab/hiveserver.service.keytab")
hiveserver.copy_from_host(source="${./minica/hiveserver/keystore.jks}",target="/var/security/keystore.jks")


nn2.succeed("""
kinit -k -t /var/security/keytab/nn.service.keytab hdfs/nn2 && \
hadoop fs -mkdir -p    /home/hive && \
hadoop fs -chown hive:hadoop    /home/hive  && \
hadoop fs -mkdir       /tmp  && \
hadoop fs -chown hdfs:hadoop   /tmp &&  \
hadoop fs -chmod g+w   /tmp &&  \
hadoop fs -mkdir -p    /user/hive  && \
hadoop fs -chown hive:hadoop   /user/hive &&  \
hadoop fs -mkdir    /user/hive/warehouse  && \
hadoop fs -chmod g+w   /user/hive/warehouse 
""")




hiveserver.wait_for_unit("mysql.service")
hiveserver.succeed("schematool -dbType mysql -initSchema")
hiveserver.succeed("systemctl restart hive-init")
hiveserver.succeed("systemctl restart hiveserver")
hiveserver.wait_for_open_port(10000)
hiveserver.succeed("""
kinit -k -t /var/security/keytab/hiveserver.service.keytab hive/hiveserver && \
beeline -u \"jdbc:hive2://hiveserver:10000/;principal=hive/hiveserver@TEST.REALM\" -e \"SHOW TABLES;\"
""")
  '';
} {
  inherit pkgs;
  inherit (pkgs) system;
}


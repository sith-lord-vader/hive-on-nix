{ config, lib, pkgs, ... }:

{
  options.services = {
    kerberos.hadoop = {
      enable = mkEnableOption "whether to kerberize the hadoop services present on this node. Creates the relevant principals and adds them to {core,hdfs,yarn,hive,...}-site.xml.";
      realm = mkOption {
        type = types.str;
        default = null;
        description = "realm in which Hadoop principals are to be created.";
      };
    };
    #   hadoop.enableSsl = mkEnableOption "enable ssl access for hdfs, and by extension for all services. necessary for kerberizesd clusters.";
  };

  config = mkIf kerberos.hadoop.enable
    (mkAssert krb5.enable "krb5 must exist in order to kerberize the cluster!"
      {
        
        services.hadoop = mkMerge [
          # (mkIf config.services.hadoop.enableSsl {}) # SSL is recommended but not required for kerberized Hadoop clusters. https://hadoop.apache.org/docs/stable/hadoop-project-dist/hadoop-common/SecureMode.html#Data_Encryption_on_HTTP
          {
            # enableSsl = true;
            coreSite = {
              "hadoop.security.authentication" = "kerberos";
              "hadoop.security.authorization" = "true";
              "hadoop.rpc.protection" = "authentication";
            };
            hdfsSite = {
              "dfs.block.access.token.enable" = "true";
              "dfs.namenode.kerberos.principal" = "hdfs/_HOST@${config.services.kerberos.hadoop.realm}";
              "dfs.namenode.keytab.file" = "/var/security/keytab/nn.service.keytab";
              "dfs.journalnode.kerberos.principal" = "hdfs/_HOST@${config.services.kerberos.hadoop.realm}";
              "dfs.journalnode.keytab.file" = "/var/security/keytab/jn.service.keytab";
              "dfs.datanode.kerberos.principal" = "hdfs/_HOST@${config.services.kerberos.hadoop.realm}";
              "dfs.datanode.keytab.file" = "/var/security/keytab/dn.service.keytab";
            };

            yarnSite = {
              "yarn.resourcemanager.principal" = "yarn/_HOST@${config.services.kerberos.hadoop.realm}";
              "yarn.resourcemanager.keytab" = "/var/security/keytab/rm.service.keytab";
              "yarn.nodemanager.principal" = "yarn/_HOST@${config.services.kerberos.hadoop.realm}";
              "yarn.nodemanager.keytab" = "/var/security/keytab/nm.service.keytab";
            };
          }
        ];
      });
}

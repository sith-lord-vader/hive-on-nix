{ config, lib, pkgs, ... }:

{
  # to be submitted to nixpkgs.
  options.services.kerberos_server = {
    primary = mkEnableOption "is this kdc server primary? Setting this to true will run kprop replicator with target kdcs specified in `config.services.kerberos_server.kdcs` every 2 minutes. Setting it to false will instead run the kpropd listener.";

    kdcs = mkOption {
      type = with types; listOf str;
      default = [ ];
      description = "replica KDCs to which the primary KDC should replicate the user database.";
    };
  };

  config = mkIf config.services.kerberos_server.enable {
    systemd = mkMerge [
      (mkIf config.ixnay.kerberos.primary {

        timers.kprop = {
          wantedBy = [ "multi-user.target" ];
          timerConfig = {
            Persistent = "true";
            OnBootSec = "1min";
            OnUnitActiveSec = "2min";
          };
        };

        services.kprop = {
          path = [ config.krb5.kerberos ];
          script = ''
            #!${pkgs.bash}/bin/bash

            kdb5_util dump /var/lib/krb5kdc/replica_datatrans

            for kdc in ${concatStringsSep " " config.ixnay.kerberos.kdcs}
              do
                  kprop -f /var/lib/krb5kdc/replica_datatrans $kdc
              done

          '';
        };

        services.kadmind.environment.KRB5_KDC_PROFILE = pkgs.lib.mkForce
          (pkgs.writeText "kdc.conf" ''
            ${builtins.readFile config.environment.etc."krb5kdc/kdc.conf".source}
            	'');
      })

      (mkIf (!config.ixnay.kerberos.primary) {
        services.kpropd = {
          description = "Kerberos replication listener";
          wantedBy = [ "multi-user.target" ];
          preStart = ''
            mkdir -m 0755 -p /var/lib/krb5kdc
          '';
          serviceConfig.ExecStart = "${config.krb5.kerberos}/bin/kpropd -P 754 -D -s /etc/krb5.keytab --pid-file=/run/kpropd.pid"; # remember that this means we need to create krb5.keytab. TODO write the init script that does this.
          restartTriggers = config.systemd.services.kadmind.restartTriggers;
          environment = config.systemd.services.kdc.environment;
        };
      })
    ];
  };
}

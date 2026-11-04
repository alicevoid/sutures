{ config, pkgs, ... }:

# Outgoing mail through SMTP2GO, for alerts. Every sender mails "root"; the aliases file maps it to
#   a real address, so the address stays out of this public repo. Both come from secrets/hosts.yaml.
#   Failure mails: add  onFailure = [ "notify-failure@%n.service" ];  to a unit.

{
  sops.secrets.msmtp-password = { };
  sops.secrets.mail-aliases = { };

  programs.msmtp = {
    enable = true;
    setSendmail = true;
    defaults.aliases = config.sops.secrets.mail-aliases.path;
    accounts.default = {
      host = "mail.smtp2go.com";
      port = 2525;
      auth = "plain";
      tls = true;
      tls_starttls = true;
      user = "auth.pvc.tools";
      from = "no-reply@pvc.tools";
      # absolute path: smartd and ZED run the mailer with an almost empty PATH
      passwordeval = "${pkgs.coreutils}/bin/cat ${config.sops.secrets.msmtp-password.path}";
    };
  };

  systemd.services."notify-failure@" = {
    description = "Mail the status of %i";
    serviceConfig.Type = "oneshot";
    scriptArgs = "%i";
    path = [ pkgs.msmtp ];
    script = ''
      unit="$1"
      {
        printf 'Subject: [%s] %s failed\n\n' "${config.networking.hostName}" "$unit"
        systemctl status --no-pager --full "$unit" || true
        echo
        journalctl -u "$unit" -n 50 --no-pager || true
      } | msmtp root
    '';
  };
}

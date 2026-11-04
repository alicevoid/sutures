{ config, pkgs, ... }:

# Outgoing mail through SMTP2GO, for alerts. Every sender mails "root"; the aliases file maps it to
#   a real address, so the address stays out of this public repo. Both files are root-only (0600)
#   and made by hand until SOPS.
#   Failure mails: add  onFailure = [ "notify-failure@%n.service" ];  to a unit.

{
  programs.msmtp = {
    enable = true;
    setSendmail = true;
    defaults.aliases = "/var/lib/secrets/mail-aliases";
    accounts.default = {
      host = "mail.smtp2go.com";
      port = 2525;
      auth = true;
      tls = true;
      tls_starttls = true;
      user = "auth.pvc.tools";
      from = "no-reply@pvc.tools";
      # absolute path: smartd and ZED run the mailer with an almost empty PATH
      passwordeval = "${pkgs.coreutils}/bin/cat /var/lib/secrets/msmtp-password";
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

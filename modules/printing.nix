{ config, ... }:

# Epson WF-7840 over driverless IPP. Needs a DHCP reservation for 10.0.0.195.

{
  services.printing.enable = true;

  # Not hardware.printers.ensurePrinters: it runs lpadmin -m everywhere in cups' ExecStartPost,
  # so an unreachable printer fails cups.service.
  systemd.services.printer-wf7840 = {
    description = "Add the WF-7840 CUPS queue";
    requires = [ "cups.service" ];
    after = [
      "cups.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [ config.services.printing.package ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "5min";
    };
    script = ''
      lpadmin -p WF-7840 -E -L home -m everywhere -v ipp://10.0.0.195/ipp/print
    '';
  };
}

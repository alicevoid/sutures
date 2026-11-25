{ config, pkgs, ... }:

# Epson WF-7840 over driverless IPP. Needs a DHCP reservation for 10.0.0.195.

{
  services.printing.enable = true;

  # Not hardware.printers.ensurePrinters: it runs lpadmin -m everywhere in cups' ExecStartPost,
  # so an unreachable printer fails cups.service.
  # -m everywhere fetches the PPD from the printer, so a timer retries until the printer is on.
  # The queue is made once. To apply new options, run `lpadmin -x WF-7840` and let the timer remake it.
  systemd.services.printer-wf7840 = {
    description = "Add the WF-7840 CUPS queue";
    requires = [ "cups.service" ];
    after = [
      "cups.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    path = [
      config.services.printing.package
      pkgs.bash
    ];
    serviceConfig.Type = "oneshot";
    # The generated PPD defaults InputSlot to Main, which pins every job to Cassette 1.
    # Auto lets the printer match the tray by media size.
    script = ''
      if lpstat -p WF-7840 >/dev/null 2>&1; then exit 0; fi
      if ! timeout 3 bash -c '</dev/tcp/10.0.0.195/631' 2>/dev/null; then
        echo "WF-7840 unreachable, retrying later"
        exit 0
      fi
      lpadmin -p WF-7840 -E -L home -m everywhere -v ipp://10.0.0.195/ipp/print -o InputSlot=Auto
    '';
  };
  systemd.timers.printer-wf7840 = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnActiveSec = "1min";
      OnUnitInactiveSec = "10min";
    };
  };
}

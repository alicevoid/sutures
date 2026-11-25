{ config, pkgs, ... }:

# Epson WF-7840 over driverless IPP.
#   10.0.0.194 is a DHCP reservation in the router. If you change it there, change host here.
#   Its mDNS name, EPSON4FBEAC.local, finds it if the address is ever lost.

let
  host = "10.0.0.194";
  uri = "ipp://${host}/ipp/print";
in
{
  services.printing.enable = true;

  # Not hardware.printers.ensurePrinters: it runs lpadmin -m everywhere in cups' ExecStartPost,
  # so an unreachable printer fails cups.service.
  # -m everywhere fetches the PPD from the printer, so a timer retries until the printer is on.
  # The queue is made once; later runs only correct its address, so a changed host above
  # reaches queues that already exist. To apply new options, run `lpadmin -x WF-7840` and let
  # the timer remake it.
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
      pkgs.gnugrep
    ];
    serviceConfig.Type = "oneshot";
    # The generated PPD defaults InputSlot to Main, which pins every job to Cassette 1.
    # Auto lets the printer match the tray by media size.
    script = ''
      if lpstat -p WF-7840 >/dev/null 2>&1; then
        if lpstat -v WF-7840 | grep -qF '${uri}'; then exit 0; fi
        lpadmin -p WF-7840 -v '${uri}'
        exit 0
      fi
      if ! timeout 3 bash -c '</dev/tcp/${host}/631' 2>/dev/null; then
        echo "WF-7840 unreachable, retrying later"
        exit 0
      fi
      lpadmin -p WF-7840 -E -L home -m everywhere -v '${uri}' -o InputSlot=Auto
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

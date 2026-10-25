{ pkgs, ... }:

# Home Assistant: bare metal on ephara, state in /var/lib/hass (NVMe)
#   Restored from the Docker backup (HA 2026.4.4, 2026-10-21). Routed as ha.pvc.tools via pharika's Gateway.
#   NOTE: "add-ons" need the HAOS Supervisor, so each one is its own NixOS service here.

let
  # Our own themes, kept in the repo (hass/themes/*.yaml)
  localThemes = pkgs.runCommand "hass-local-themes" { passthru.isHomeAssistantTheme = true; } ''
    mkdir -p $out/themes
    cp ${./hass/themes}/*.yaml $out/themes/
  '';

  # TCL Home (unofficial): the TCL portable AC, through TCL's cloud (TCL Home app account)
  #   Not in nixpkgs. Packaged here like nixpkgs' own custom components.
  #   To bump: change version, set hash = "", rebuild, paste back what nix prints.
  tclHome = pkgs.buildHomeAssistantComponent rec {
    owner = "nemesa";
    domain = "tcl_home_unofficial";
    version = "3.16.0";
    src = pkgs.fetchFromGitHub {
      owner = "nemesa";
      repo = "ha-tcl-home-unofficial-integration";
      tag = version;
      hash = "sha256-p+vmRfrpk1nlgReI5RjJWjL84QSndKWQOJXm9ktPVlE=";
    };
    # manifest.json lists no requirements, but aws_iot.py imports boto3 (jwt ships with HA)
    dependencies = [ pkgs.home-assistant.python3Packages.boto3 ];
    dontBuild = true;
    doCheck = false;
  };
in
{
  services.home-assistant = {
    enable = true;

    # Integrations from the restored config entries (.storage/core.config_entries)
    extraComponents = [
      # defaults
      "default_config"
      "met"
      "esphome"
      "isal" # faster compression, quiets a startup warning

      # in use
      "androidtv_remote" # Google TV Streamer 4K, also found by discovery
      "backup"
      "cast"
      "go2rtc" # the module puts the go2rtc binary on HA's path
      "google_translate"
      "group"
      "mobile_app"
      "radio_browser"
      "shopping_list"
      "sonos"
      "sun"

      # radios
      "zha" # Sonoff Zigbee 3.0 Dongle Plus (ZNP), also grants serial access
      "matter" # talks to services.matter-server below
      "thread" # reads the Google TV Streamer's Thread network

      # companions
      "music_assistant"
    ];

    customComponents = with pkgs.home-assistant-custom-components; [
      scheduler # alarm-clock style schedules (pairs with scheduler-card)
    ] ++ [
      tclHome # TCL two-hose portable AC (TCL Home app)
    ];

    # Cards, registered as Lovelace resources automatically
    #   NOTE: only works because `config` below is managed here (not null)
    customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
      card-mod # theme anything per card
      mushroom # clean controls, incl. a good climate (AC) card
      scheduler-card
    ];

    themes = [
      pkgs.home-assistant-themes.catppuccin
      localThemes # slate
    ];

    # configuration.yaml, translated from the restored one
    #   NOTE: UI-made automations, scenes and scripts still live in their yaml files in /var/lib/hass
    config = {
      default_config = { };

      automation = "!include automations.yaml";
      script = "!include scripts.yaml";
      scene = "!include scenes.yaml";

      # NOTE: no `http:` block. Since HA 2026.10 it lives in the UI (Settings > System > Network).
      #   The old block (use_x_forwarded_for, trusted_proxies 127.0.0.1 + 10.0.0.0/8) was imported on first boot.
    };
  };

  # Matter controller for HA (ws://localhost:5580)
  #   Devices are shared in from Google Home (Matter multi-admin)
  #   NOTE: matterjs, not python matter-server: 8.1.2 dies at startup parsing a DCL cert (2026-10-23)
  services.matterjs-server = {
    enable = true;
    extraArgs = [ "--primary-interface=br0" ]; # link-local IPv6 for Matter/Thread (br0 holds the LAN, see configuration.nix)
  };

  # Music Assistant (web UI on :8095), plays to Sonos, Cast and HA media players
  services.music-assistant = {
    enable = true;
    providers = [
      "builtin"
      "chromecast"
      "hass"
      "hass_players"
      "radiobrowser"
      "sonos"
    ];
  };
}

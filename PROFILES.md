# Profiles & on-demand tools

The goal of this repo is to keep the **always-installed** surface small and load
specialised tooling only when needed. There are two mechanisms:

| Kind | For | How you load it | Gone when |
|------|-----|-----------------|-----------|
| **Specialisation** | Tools needing system privileges (drivers, FHS, udev, capabilities) | `switch-to-configuration` into the variant | you switch back |
| **devShell** | Pure user-space tools | `nix develop .#<name>` | you exit the shell |

Live cross-checks (source of truth is always the flake):

- `nix flake show` — lists every devShell
- `ls /run/current-system/specialisation` — lists built specialisations on this host

---

## Specialisations

### `gaming`  — defined in `profiles/gaming.nix`
Steam + 32-bit GPU drivers + OBS. Only laptops (athreos, kunoros) build it.

```bash
# activate (Steam becomes available, no reboot)
sudo /run/current-system/specialisation/gaming/bin/switch-to-configuration switch

# deactivate (back to your normal system)
sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
```

Games themselves are downloaded/deleted by Steam in your home dir — Nix only
manages the client, so "install, play, be done" is just Steam's own uninstall.

---

## devShells

### `dev`  — defined in `flake.nix` (`devShells.dev`)
```bash
nix develop .#dev
```
Currently: `python3`, `gh`, `git-extras`.

---

## Ad-hoc, no profile needed

For a one-off tool you don't want to keep, skip profiles entirely:

```bash
nix shell nixpkgs#blender     # on PATH until you exit the shell
nix run  nixpkgs#some-tool    # run once
```

---

## Adding a profile later

- **Privileged** → new file in `profiles/`, reference it in the host's module
  list in `flake.nix`, add a row above.
- **User-space** → add an entry to `devShells` in `flake.nix`, add a row above.

Candidates currently living in `home/alice.nix` that could be demoted to
profiles as you go: `filezilla`, `zoom-us`, `ffmpeg`, `pngquant`.

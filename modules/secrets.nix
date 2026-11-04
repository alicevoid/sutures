{ ... }:

# sops-nix: decrypts sutures/secrets/* at activation into /run/secrets (tmpfs, root 0400 by default).
#   Each host decrypts with its own SSH host key. Rules for who can open what: .sops.yaml.
#   Edit a file on athreos: sops secrets/<file>.yaml

{
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.gnupg.sshKeyPaths = [ ];
  sops.defaultSopsFile = ../secrets/hosts.yaml;
}

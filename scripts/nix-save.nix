{ ... }:

let
  repoArchive = "https://github.com/not-a-longneck/simple-nixos-vm/archive/refs/heads/main.tar.gz";
  configDir = "/etc/nixos";
in
{
  environment.interactiveShellInit = ''
    nix-update() {
      echo "⬇️ Step 1: Downloading and overwriting from GitHub..."
      curl -sL "${repoArchive}" | sudo tar -xz -C "${configDir}" --strip-components=1 --overwrite
      
      echo "❄️ Step 2: Rebuilding NixOS..."
      if sudo NIXPKGS_ALLOW_UNFREE=1 nixos-rebuild switch --cores 1 -j 1; then
        gen_num=$(readlink /nix/var/nix/profiles/system | cut -d- -f2)
        echo "✨ Success! Updated to Generation $gen_num!"
      else
        echo "❌ Rebuild failed!"
      fi
    }
  '';
}
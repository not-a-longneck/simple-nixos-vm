# /etc/nixos/configuration.nix
{ config, pkgs, ... }:

let
  isEfi = builtins.pathExists /sys/firmware/efi;
  biosDevice = if builtins.pathExists /dev/vda then "/dev/vda"
               else if builtins.pathExists /dev/sda then "/dev/sda"
               else "/dev/nvme0n1";
in
{
  imports = [
    ./hardware-configuration.nix
    ./scripts/nix-save.nix
    ./scripts/compressall.nix
  ];

  # ==============================
  # HARDWARE
  # ==============================

  boot.loader.grub = {
    enable = true;
    device = if isEfi then "nodev" else biosDevice;
    efiSupport = isEfi;
    useOSProber = true;
  };

  boot.loader.efi.canTouchEfiVariables = isEfi;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  boot.kernelModules = [ "fuse" ];
  environment.etc."fuse.conf".text = ''
    user_allow_other
  '';

  # ==============================
  # PRIVACY
  # ==============================

  services.journald.extraConfig = ''
    Storage=volatile
    ForwardToSyslog=no
    ForwardToKMsg=no
    ForwardToConsole=no
    ForwardToWall=no
  '';

  fileSystems."/home/admin/.cache" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "nosuid" "nodev" "relatime" "size=512M" ];
  };

  systemd.coredump.enable = false;

  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  # ==============================
  # DESKTOP ENVIRONMENT
  # ==============================

  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  xdg.portal.enable = true;


  ### KDE (comment out to disable)
  services.displayManager.defaultSession = "plasmax11";
  services.desktopManager.plasma6.enable = true;


  ### XFCE (comment out to disable)
  # services.displayManager.defaultSession = "xfce";
  # services.xserver.desktopManager.xfce.enable = true;
  # xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];



  users.users.admin = {
    isNormalUser = true;
    description = "admin";
    extraGroups = [ "networkmanager" "wheel" "video" "render" "storage" "disk" ];
    hashedPassword = "$6$Osqk1/PTMVPFxz.R$xnhXNz5ePRgPQZtGMaXlSDInDsrwNocuRqVmTfZcq4ujAer6PiesG27vZpkxdMJh3gtSzP9qOlTs8CTP9Pf.f/";
  };

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    extraConfig.pipewire."92-low-latency" = {
      "context.properties" = {
        "default.clock.rate" = 48000;
        "default.clock.quantum" = 1024;
        "default.clock.min-quantum" = 512;
        "default.clock.max-quantum" = 2048;
      };
    };
  };

  # ==============================
  # APPS AND TOOLS
  # ==============================

  nixpkgs.config.allowUnfree = true;
  services.flatpak.enable = true;
  programs.firefox.enable = true;

  environment.systemPackages = with pkgs; [
    # System Utilities
    spice-vdagent
    cifs-utils
    veracrypt
    ntfs3g

    # GUI Applications
    vlc
    tor-browser
    peazip
    czkawka-full
    qdirstat
    kdePackages.filelight
    kdePackages.kate
    rustdesk-flutter
  ];

  # Set default MIME apps system-wide
  environment.etc."xdg/mimeapps.list".text = ''
    [Default Applications]
    video/mp4=vlc.desktop
    video/x-matroska=vlc.desktop
    video/webm=vlc.desktop
    video/quicktime=vlc.desktop
    video/x-msvideo=vlc.desktop
    video/mpeg=vlc.desktop
    video/ogg=vlc.desktop
    video/x-flv=vlc.desktop
    video/3gpp=vlc.desktop
  '';

  # ==============================
  # VM SPECIFIC
  # ==============================

  services.spice-vdagentd.enable = true;

  # ================================
  # MOUNTS AND FILESYSTEM
  # ================================

  fileSystems."/mnt/tower/backups" = {
    device = "//192.168.1.53/backups";
    fsType = "cifs";
    options = [
      "guest"
      "uid=1000"
      "gid=100"
      "rw"
      "iocharset=utf8"
      "file_mode=0777"
      "dir_mode=0777"
      "noperm"
      "_netdev"
      "x-systemd.automount"
      "x-systemd.idle-timeout=60"
    ];
  };

  fileSystems."/mnt/shared" = {
    device = "share-home";
    fsType = "virtiofs";
    options = [
      "nofail"
      "x-systemd.automount"
      "x-systemd.idle-timeout=60"
    ];
  };

  services.udev.extraRules = ''
    KERNEL=="dm-*", ENV{ID_FS_USAGE}=="filesystem", OWNER="admin", GROUP="users", MODE="0775"
  '';

  # ================================
  # FLATPAK SETUP SERVICE
  # ================================

  systemd.services.flatpak-setup = {
    description = "Install and configure Flatpak apps";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "flatpak-system-helper.service" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if [ -f /var/lib/flatpak-setup-done ]; then exit 0; fi

      ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
      ${pkgs.flatpak}/bin/flatpak install -y flathub org.jdownloader.JDownloader
      #${pkgs.flatpak}/bin/flatpak install -y flathub com.rustdesk.RustDesk
      ${pkgs.flatpak}/bin/flatpak override org.jdownloader.JDownloader \
        --filesystem=xdg-download:rw \
        --filesystem=/tmp:rw \
        --filesystem=/mnt:rw \
        --filesystem=/mnt/veracrypt1/:rw \
        --socket=x11 \
        --socket=wayland \
        --socket=fallback-x11 \
        --share=network \
        --share=ipc \
        --talk-name=org.freedesktop.NetworkManager

      touch /var/lib/flatpak-setup-done
    '';
  };

  # ================================
  # ACTIVATION SCRIPT
  # ================================

  system.activationScripts.adminHomeSetup = {
    text = ''
      # 1. Unraid Symlink
      ln -sfn /mnt/tower/backups /home/admin/Unraid

      # 2. Config Files (VLC, Tor, Plasma)
      mkdir -p /home/admin/.config/vlc
      cat > /home/admin/.config/vlc/vlcrc << 'EOF'
[core]
metadata-network-access=0
show-hiddenfiles=1
playlist-tree=0
recursive=expand
random=1
loop=1
[qt]
qt-privacy-ask=0
qt-notification=0
qt-video-autoresize=0
EOF

      mkdir -p "/home/admin/.tor-project/TorBrowser/Data/Browser/profile.default"
      cat > "/home/admin/.tor-project/TorBrowser/Data/Browser/profile.default/user.js" << 'EOF'
user_pref("javascript.enabled", false);
user_pref("extensions.torlauncher.prompt_at_startup", false);
user_pref("network.bootstrapped", true);
user_pref("intl.accept_languages", "en-US, en");
user_pref("intl.locale.requested", "en-US");
user_pref("browser.toolbars.bookmarks.visibility", "never");
EOF

      cat > /home/admin/.config/ksmserverrc << 'EOF'
[General]
loginMode=emptySession
EOF

      cat > /home/admin/.config/dolphinrc << 'EOF'
[NKCoreSettings]
LocalFilesPreviews=false
RemoteFilesPreviews=false
EOF

      # 3. Enforce Permissions
      chown -R admin:users /home/admin/.config /home/admin/.tor-project /home/admin/Unraid
      chown -R admin:users /etc/nixos
      chmod -R 755 /etc/nixos
    '';
  };

  # ===============================
  # USER SETTINGS
  # ===============================

  time.timeZone = "Europe/Copenhagen";
  i18n.defaultLocale = "en_DK.UTF-8";

  console.keyMap = "dk";
  services.xserver.xkb = {
    layout = "dk";
    variant = "";
  };

  environment.shellAliases = {
    copypaste = "spice-vdagent";
  };

  system.stateVersion = "25.11";
}

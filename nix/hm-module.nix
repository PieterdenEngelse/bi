# Home Manager module for nixdash.
#
# Installs the engine and runs it as a *user* service. Deliberately a user
# unit, not a system one: the engine holds no privilege and reports only what
# you can already read yourself. If this ever needs root, the design has gone
# wrong - see the "no escalation" rule in the README.
#
# Usage (channel-based Home Manager, as configured on this machine):
#
#   # ~/.config/home-manager/modules/nixdash.nix
#   { ... }: {
#     imports = [ /home/pde/Projects/nixdash/nix/hm-module.nix ];
#     services.nixdash.enable = true;
#   }
#
# then add it to the imports list in home.nix.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.nixdash;

  # Built once and used twice: as the menu entry and as the autostart file.
  # Referencing the generated entry by its runtime path instead would not
  # exist at evaluation time.
  desktopItem = pkgs.makeDesktopItem {
    name = "nixdash";
    desktopName = "nixdash";
    comment = "NixOS config and monitoring";
    # The UI reads NIXDASH_PORT to find the engine, so the entry has to carry
    # whatever port the service was configured with.
    exec = "env NIXDASH_PORT=${toString cfg.port} ${lib.getExe cfg.ui.package}";
    # Themed name, resolved from hicolor below - not an absolute path. The
    # icon is scalable, so the theme lookup is what lets a 24px panel and a
    # 48px menu each get a crisp render from the one SVG.
    icon = "nixdash";
    terminal = false;
    categories = [
      "System"
      "Monitor"
    ];
  };
in
{
  options.services.nixdash = {
    enable = lib.mkEnableOption "the nixdash monitoring engine";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./engine.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./engine.nix { }";
      description = "The nixdash engine package to run.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3100;
      description = ''
        Port on 127.0.0.1 to listen on.

        Only the port is configurable, never the address: the engine has no
        authentication and no TLS, so it binds loopback unconditionally.
      '';
    };

    logLevel = lib.mkOption {
      type = lib.types.str;
      default = "nixdash_engine=info,tower_http=warn";
      example = "nixdash_engine=debug,tower_http=debug";
      description = "Value of RUST_LOG for the service.";
    };

    ui = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the desktop UI and a menu entry for it.";
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.callPackage ./ui.nix { };
        defaultText = lib.literalExpression "pkgs.callPackage ./ui.nix { }";
        description = "The nixdash desktop UI package.";
      };

      autostart = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open the UI at login. Off by default: the engine collects with no UI running, so this is about whether you want a window every boot, not whether monitoring happens.";
      };
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Start at login. Turn this off to keep the unit installed but
        hand-started with `systemctl --user start nixdash-engine`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # A dashboard you have to remember to launch is a dashboard you will not
    # look at. Installing the desktop item puts nixdash in the application
    # menu; autostart additionally opens it at login.
    home.packages =
      [ cfg.package ]
      ++ lib.optionals cfg.ui.enable [
        cfg.ui.package
        desktopItem
      ];

    # The icon, installed into the user's hicolor theme so `Icon=nixdash`
    # resolves from the menu entry, the panel launcher and the window manager
    # alike. scalable/ rather than a fixed size: one SVG serves every size,
    # and no icon cache needs regenerating for scalable entries.
    home.file.".local/share/icons/hicolor/scalable/apps/nixdash.svg" =
      lib.mkIf cfg.ui.enable { source = ../assets/nixdash.svg; };

    # XDG autostart rather than a systemd graphical-session unit: Xfce honours
    # ~/.config/autostart reliably, and its graphical-session.target wiring is
    # less dependable.
    xdg.configFile."autostart/nixdash.desktop" = lib.mkIf (cfg.ui.enable && cfg.ui.autostart) {
      source = "${desktopItem}/share/applications/nixdash.desktop";
    };

    systemd.user.services.nixdash-engine = {
      Unit = {
        Description = "nixdash engine (NixOS monitoring, loopback only)";
        Documentation = "file://${../README.md}";
        # Without this the service can start before the user session has a
        # D-Bus socket, and the user-scope half of the failed-units collector
        # reports "unavailable" for the first few samples.
        After = [ "graphical-session-pre.target" ];
      };

      Service = {
        Type = "simple";
        ExecStart = lib.getExe cfg.package;
        Environment = [
          "NIXDASH_PORT=${toString cfg.port}"
          "RUST_LOG=${cfg.logLevel}"
        ];
        Restart = "on-failure";
        RestartSec = "5s";

        # This service used to be tightly sandboxed, on the grounds that the
        # engine needed no privilege at all. It now runs actions via pkexec,
        # and that changes what is possible here.
        #
        # pkexec is setuid and execs the target program *in place* - same
        # cgroup, same namespaces, same mount view. Whatever restricts this
        # unit restricts `nixos-rebuild switch` too. So the old settings did
        # not merely fail to help, they broke the feature in ways that would
        # have been miserable to diagnose:
        #
        #   NoNewPrivileges       setuid cannot take effect; pkexec just fails
        #   ProtectSystem=strict  /nix/store read-only - no build can finish
        #   RestrictNamespaces    removes the namespaces Nix sandboxes builds in
        #   ProtectKernel*        activation sets sysctls; systemd writes cgroups
        #   ProtectHome           nix as root wants a writable /root
        #   PrivateTmp            builds use /tmp, and would not see the real one
        #   MemoryDenyWriteExecute  gratuitous risk for anything with a JIT
        #
        # Removing them is the honest price of the Run button, not an
        # oversight.
        #
        # Nothing is left, and that is not laziness either. The two that looked
        # free - LockPersonality and SystemCallArchitectures - are implemented
        # with **seccomp**, and systemd cannot install a seccomp filter in an
        # unprivileged user unit without also setting NoNewPrivileges. So they
        # silently re-enable the one setting that makes setuid a no-op:
        #
        #   systemctl --user show nixdash-engine -p NoNewPrivileges  ->  no
        #   grep NoNewPrivs /proc/$(pidof nixdash-engine)/status     ->  1
        #
        # The unit claims one thing and the kernel reports another, and pkexec
        # fails with "pkexec must be setuid root" - which sounds like a broken
        # polkit install, not a sandbox setting you chose. NoNewPrivs is also
        # inherited and can never be cleared, so a stale process keeps it
        # across a config change until it is actually restarted.
        #
        # If you add ANY seccomp-based option here (SystemCallFilter,
        # MemoryDenyWriteExecute, RestrictRealtime, RestrictSUIDSGID,
        # LockPersonality, SystemCallArchitectures), privileged actions stop
        # working and the error will not point here.
      };

      Install = lib.mkIf cfg.autoStart {
        WantedBy = [ "default.target" ];
      };
    };
  };
}

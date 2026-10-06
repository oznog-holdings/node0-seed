# A herdr server for the builder's own account (agent), so the orchestrator (Rigger) can run the builder's Claude Code
# session in a pane that outlives any client (20260930). Same herdr and settings as the site agents'
# (site-agents.nix). No unit here starts or prompts Claude: Rigger starts that session by hand.
{ config, lib, pkgs, ... }:
let
  H = "/home/agent";
  # herdr 0.9.3 from the vendor's release, the same binary and sha256 as tender's
  # (a flat fetch, so the sha256 is the file's own, comparable with tender's; then made executable)
  herdr = pkgs.runCommand "herdr-0.9.3" { src = pkgs.fetchurl {
    url = "https://github.com/herdrdev/herdr/releases/download/v0.9.3/herdr-linux-x86_64";
    sha256 = "18a8dc65f1c2fa485884344356dea1cfd911c6f06cf46fa78e193f4087f4dba7";
  }; } "install -m 755 $src $out";
  only = { ConditionUser = "agent"; };
in {
  # declared: NixOS removes lingering it doesn't declare
  users.users.agent.linger = true;

  # every inference request's timings (prompt read, cache hit, generation) into /work/agent/qwen-calls.tsv, from the
  # server's own log on compute (tools/qwen-calls.sh; the orchestrator's request, 20260930)
  systemd.user.timers.keel-qwen-calls = {
    unitConfig = only; wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "*:0/10"; Persistent = true; };
  };
  systemd.user.services = {
    keel-qwen-calls = {
      unitConfig = only;
      environment.PATH = lib.mkForce "/run/current-system/sw/bin";
      serviceConfig = { Type = "oneshot"; ExecStart = "/work/agent/seed-lab/tools/qwen-calls.sh"; };
    };
    # the binary and the settings put in place; keel-herdr names only these stable paths, so a deploy that changes
    # them changes this unit alone, never keel-herdr (it would restart the server and every pane in it)
    keel-config = {
      unitConfig = only; wantedBy = [ "default.target" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = ''
        ${pkgs.coreutils}/bin/install -d -m 700 ${H}/.local/bin
        ${pkgs.coreutils}/bin/ln -sfn ${herdr} ${H}/.local/bin/herdr
        ${pkgs.coreutils}/bin/install -D -m 600 ${./site-agents/herdr-config.toml} ${H}/.config/herdr/config.toml
      '';
    };
    keel-herdr = {
      unitConfig = only; wantedBy = [ "default.target" ];
      after = [ "keel-config.service" ]; wants = [ "keel-config.service" ];   # wants: a config refresh never restarts it
      # stable paths only (NixOS would put glibc's and tzdata's store paths here, and their updates would restart it)
      environment = {
        PATH = lib.mkForce "${H}/.local/bin:/etc/profiles/per-user/agent/bin:/run/current-system/sw/bin";
        LOCALE_ARCHIVE = lib.mkForce "/run/current-system/sw/lib/locale/locale-archive";
        TZDIR = lib.mkForce "/etc/zoneinfo";
      };
      serviceConfig = { ExecStart = "${H}/.local/bin/herdr server"; Restart = "always"; RestartSec = 5; WorkingDirectory = H; };
    };
  };
}

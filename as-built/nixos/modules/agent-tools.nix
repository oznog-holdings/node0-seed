# The agent tools for the site's agent account (the same declaration as on agentvm, where they
# were first proven, 20260923): Claude Code and Codex pinned to upstream releases (F-TOOLPIN),
# self-updaters off, and account connectors OFF for every seed agent (annex: "Account
# connectors stay off", "Codex connectors too"). The logins are a person's (Needs hands).
# Bump a tool: change its version and hash here, commit, promote to `deploy`.
{ config, lib, pkgs, ... }:
let
  user = "agent";
  home = config.users.users.${user}.home;
  codex-bin = pkgs.callPackage ../pkgs/codex.nix { };   # shared with the site agents (tender)
  # nixpkgs' claude-code with the release manifest (checksum from downloads.claude.ai/claude-code-releases/<v>/manifest.json)
  claude-code-pinned = pkgs.claude-code.override {
    manifest = { version = "2.1.281"; platforms."linux-x64".checksum = "56fe3da88458465fb27d7e9299dddb3fead55750fb9c2de795f233b5eea6dce1"; };
  };
in {
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "claude-code" ];
  environment.systemPackages = with pkgs; [ git jq curl ripgrep tmux remarshal bitwarden-cli nodejs claude-code-pinned codex-bin
    # python3 for the site's own scripts (netbox-sync, tools/*.py; F-AGENT-PYTHON)
    (python3.withPackages (p: [ p.requests p.pyyaml ])) pnpm ];
  # design › Development: "the package store sits on the same volume as the worktrees, since hard
  # links and reflinks only work within one filesystem. Turn on hard-link installs" (R2.18).
  # Each user's store under /work/<user>. pnpm 11 reads pnpm_config_* (npm_config_* is ignored:
  # with it, installs came out as reflinks, link count 1, 20260924); both are set.
  environment.extraInit = ''
    if [ -d "/work/$USER" ]; then
      export pnpm_config_store_dir="/work/$USER/.pnpm-store" npm_config_store_dir="/work/$USER/.pnpm-store"
      export pnpm_config_package_import_method=hardlink npm_config_package_import_method=hardlink
    fi
  '';

  # The tools' own directories exist before anything mounts over them (on the agent box
  # ~/.claude and ~/.codex are bind mounts from /work, modules/work-state.nix).
  system.activationScripts.agentToolDirs = {
    deps = [ "users" ];
    text = "install -d -o ${user} -g ${user} -m 0700 ${home}/.claude ${home}/.codex";
  };

  # Claude Code: account connectors off, merged into the agent's settings.json (the person's own
  # choices in that file are kept). Codex: connectors ("apps") off, gpt-6.1-sol (needs 0.159+) with medium
  # reasoning, no update check; merged, never replaced by a failed or empty merge.
  # A service after the directories are mounted, not an activation script: activation runs
  # before the mounts, so it would write into the directory the bind mount then hides
  # (F-REBUILD-STATE, 20260924). Runs at boot and again whenever this script changes.
  systemd.services.seed-agent-tool-config = {
    description = "Merge the seed's settings into the agent's Claude Code and Codex configs";
    wantedBy = [ "multi-user.target" ];
    unitConfig.RequiresMountsFor = [ "${home}/.claude" "${home}/.codex" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      d=${home}/.claude; f=$d/settings.json
      install -d -o ${user} -g ${user} -m 0700 $d
      [ -s $f ] || echo '{}' > $f
      ${pkgs.jq}/bin/jq '.env = ((.env // {}) + {"ENABLE_CLAUDEAI_MCP_SERVERS": "false"})' $f > $f.new && [ -s $f.new ] && mv $f.new $f || rm -f $f.new
      chown ${user}:${user} $f; chmod 0600 $f
      d=${home}/.codex; f=$d/config.toml
      install -d -o ${user} -g ${user} -m 0700 $d
      [ -s $f ] || : > $f
      if (set -o pipefail; ${pkgs.remarshal}/bin/remarshal -if toml -of json $f \
          | ${pkgs.jq}/bin/jq '.model = "gpt-6.1-sol" | .model_reasoning_effort = "medium"
                               | .check_for_update_on_startup = false | .features.apps = false' \
          | ${pkgs.remarshal}/bin/remarshal -if json -of toml > $f.new) && [ -s $f.new ]; then
        mv $f.new $f
      else
        rm -f $f.new; echo "agentCodexConfig: merge failed, $f left unchanged" >&2
      fi
      chown ${user}:${user} $f; chmod 0600 $f
    '';
  };

  # the builder's commit identity (the same as on laptop and agentvm)
  programs.git = {
    enable = true;
    config = { user.name = "seed builder"; user.email = "builder@seed.example.com"; init.defaultBranch = "main"; };
  };
}

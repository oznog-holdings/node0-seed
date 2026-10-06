# Codex, pinned to an upstream release by sha256, with the helper its file and shell tools need beside it. One
# derivation for the builder (agent-tools.nix) and the site agents (site-agents.nix: tender's ~/.local/bin/codex).
# Bump: change the version and both hashes (the release assets' digests), commit, promote.
{ pkgs, lib, ... }:
let
  codexVersion = "0.159.2";   # the same release as tender's (its binary sha256 1748767b…, checked 20260930)
in pkgs.stdenvNoCC.mkDerivation {
    pname = "codex"; version = codexVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${codexVersion}/codex-x86_64-unknown-linux-musl.tar.gz";
      sha256 = "26586b0d246d41a799b0ef8ee1add370f0fb0721b3709340f28db612381616ea";  # the release tarball's sha256 (as recorded for tender's install)
    };
    nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
    sourceRoot = ".";
    dontStrip = true;
    # codex runs its file and shell tools through a helper beside it; the release ships it separately (without it
    # every tool call failed, "failed to spawn code-mode host", 20260930)
    codeModeHost = pkgs.fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${codexVersion}/codex-code-mode-host-x86_64-unknown-linux-musl.tar.gz";
      sha256 = "fb6b0c4a7b24ed0728d1208ebc0061383da60debc6d61cf63e02c48ac7f7630f";  # GitHub's asset digest
    };
    installPhase = ''
      tar xzf $codeModeHost && install -Dm755 codex-code-mode-host-x86_64-unknown-linux-musl $out/bin/codex-code-mode-host
      install -Dm755 codex-x86_64-unknown-linux-musl $out/bin/codex
      wrapProgram $out/bin/codex --prefix PATH : ${lib.makeBinPath [ pkgs.ripgrep pkgs.bubblewrap ]}
    '';
    meta.mainProgram = "codex";
}

# RETIRED 20261002 (the utility tier): the reranker and speech-to-text are back on compute; this module is imported
# by no host. Kept as the record of 20260930-20261002.
# The reranker and speech-to-text, moved off compute (the orchestrator's decision, 20260930): compute keeps only
# Qwen3.8-27B and the embedder resident, with a RAM prompt cache, and these two can never take memory from them.
# Here they run on the agent box's CPU, loaded on their first request and unloaded after 5 idle minutes. Neither
# has a live user yet. The same llama.cpp release as compute (b11146), its upstream CPU build; the same model
# files as compute's pins, by sha256. Reached only by the gateway on infra (routes local-rerank, local-stt).
{ config, lib, pkgs, ... }:
let
  port = 8081;
  llama = pkgs.stdenv.mkDerivation {
    pname = "llama-cpp-cpu"; version = "b11146";
    src = pkgs.fetchurl {
      url = "https://github.com/ggml-org/llama.cpp/releases/download/b11146/llama-b11146-bin-ubuntu-x64.tar.gz";
      sha256 = "c150306eb16b5ab696f76a8bdf810c35fd98a24e82158742e6fa28f420ff8410";   # GitHub's asset digest
    };
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib pkgs.curl pkgs.openssl ];
    dontConfigure = true; dontBuild = true;
    installPhase = "mkdir -p $out/bin && cp -a . $out/bin/";
  };
  hf = repo: rev: file: sha256: pkgs.fetchurl { url = "https://huggingface.co/${repo}/resolve/${rev}/${file}"; inherit sha256; };
  reranker = hf "ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF" "a02f48bb4f057028298c21fa033da2b30d7742d5" "qwen3-reranker-0.6b-q8_0.gguf" "22c9979ce4fbcdc5acdc310c6641c32797eff1aa980b8f7a2db8a8ea23429a48";
  asr = hf "ggml-org/Qwen3-ASR-1.7B-GGUF" "36a678687ba7d07a74ca70ccb0e36902e005fb80" "Qwen3-ASR-1.7B-Q8_0.gguf" "58e22d0532d4eacaf034cfac17a6fed159f37c41390c710186783be439d1fc57";
  asrProj = hf "ggml-org/Qwen3-ASR-1.7B-GGUF" "36a678687ba7d07a74ca70ccb0e36902e005fb80" "mmproj-Qwen3-ASR-1.7B-Q8_0.gguf" "46c1d533af3f354ceb37ce855dbceff7da7fa7cf1e6a523df3b13440bd164c0d";
  # the same settings as compute's presets for these two, plus: unload after 5 idle minutes, 2 threads each
  presets = pkgs.writeText "aux-presets.ini" ''
    [qwen3-reranker-0.6b]
    model = ${reranker}
    reranking = true
    ctx-size = 4096
    parallel = 2
    batch-size = 2048
    ubatch-size = 2048
    cache-ram = 0
    threads = 2
    sleep-idle-seconds = 300

    [qwen3-asr-1.7b]
    model = ${asr}
    mmproj = ${asrProj}
    ctx-size = 8192
    parallel = 1
    cache-ram = 0
    jinja = true
    threads = 2
    sleep-idle-seconds = 300
  '';
in {
  systemd.services.seed-aux-inference = {
    description = "The reranker and speech-to-text on CPU, on demand (llama.cpp router)";
    wantedBy = [ "multi-user.target" ]; after = [ "network-online.target" ]; wants = [ "network-online.target" ];
    serviceConfig = {
      ExecStart = "${llama}/bin/llama-server --models-preset ${presets} --models-max 2 --no-webui --host 0.0.0.0 --port ${toString port}";
      DynamicUser = true; Restart = "on-failure"; RestartSec = 10;
      # bounded: it can never crowd the site agents out of the agent box's 11 GiB
      MemoryMax = "4G"; CPUQuota = "200%"; Nice = 10;
      ProtectSystem = "strict"; ProtectHome = true; PrivateTmp = true; NoNewPrivileges = true;
    };
  };
  # only the gateway (infra) may reach it
  networking.firewall.extraCommands = lib.mkAfter "iptables -A nixos-fw -p tcp -s 192.168.1.10 --dport ${toString port} -j nixos-fw-accept";
  networking.firewall.extraStopCommands = lib.mkAfter "iptables -D nixos-fw -p tcp -s 192.168.1.10 --dport ${toString port} -j nixos-fw-accept || true";
}

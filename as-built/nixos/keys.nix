# Public keys used across the site's NixOS hosts (public keys only; no secrets in the repo).
{
  # every laptop's key (design › Secrets: "every host gets every laptop's key"). laptop's
  # (seed-builder@laptop) left 20260927 when laptop went back to its owner.
  # compute, the laptop from 20260924 (user seed; also its sops/age identity)
  compute = "ssh-ed25519 AAAA...REPLACE-WITH-YOUR-PUBLIC-KEY";
  # the builder on agentvm: root on the agent box FOR THE INSTALL AND FIRST CHECKS ONLY (owner,
  # 20260924); removed by a commit once the box deploys itself from the forge (F-AGENT-ADMIN).
  agentvmBuilder = "ssh-ed25519 AAAA...REPLACE-WITH-YOUR-PUBLIC-KEY";
  # the builder on the agent box (seed-builder@agent): used where the agent box itself deploys to
  # a machine, today only the sandbox (on production hosts it is added through their own records)
  builderAgent = "ssh-ed25519 AAAA...REPLACE-WITH-YOUR-PUBLIC-KEY";
  # lab fixture, not part of the site: the orchestrator's key (annex). Remove at teardown.
  orchestrator = "ssh-ed25519 AAAA...REPLACE-WITH-YOUR-PUBLIC-KEY";
}

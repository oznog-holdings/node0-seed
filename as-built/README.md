# As built

The bench's working configuration, scripts and monitoring, exported from the build's own
repository at commit 2783daf. It is what actually ran, with these changes for publication:
addresses outside the Seed are documentation addresses (`192.0.2.0/24`, `198.51.100.0/24`), and
the bench's domain is `seed.example.com`; serials, MACs, device UUIDs and tailnet addresses are
placeholders; the owner's login account is `admin`; public keys say where yours goes; and the
encrypted secret files are left out. Everything else is as it ran. The Seed's own networks stay as
they ran (the LAN `192.168.1.0/24`, guest `192.168.20.0/24`, IoT `192.168.30.0/24`), as do
standard defaults (Docker's `172.17.0.0/16`, libvirt's `192.168.122.0/24`) and the private
blocks named in firewall rules.

Read it beside the rung pages: `site/` is the site (infra, core, the laptop and compute box, the
router), `nixos/` is the agent box's flake, and `tools/` is what the building agent used to
build, check and measure. For your own site, start from `../templates/` and your values file;
use this folder to see how a piece looked when it worked. The setup scripts under `tools/ui/`
ran once and keep the values of their day; where a setting changed later (the UPS shutdown
threshold went from 50% to 25% on 20260927), the rung pages give the current value. The rung 4b
benchmark corpus (`site/laptop/inference/bench/4b/docs.json`) copies paragraphs of the node0
pages; twenty-two of them were edited for publication after the measurement, none of them a
benchmark answer, so a rerun may differ slightly from the published figures.

Two of the bench's machines were lent for the build and went back into service, so they appear
under their roles: `laptop` (rungs 0 and 1) and `compute` (the rung 4 Mac). The two mini PCs
appear by their hardware names, Larkbox one and Larkbox two (`larkbox1`, `larkbox2`), with the
hostname each got when deployed: Larkbox two became `agent`, the agent box from rung 2;
Larkbox one stayed the spare, used as the wireless test client and as the stand-in infra box
in the recovery rehearsal (`infra-rehearsal`).

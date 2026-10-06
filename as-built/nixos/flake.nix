{
  # The site's NixOS hosts (index › Rung 2: "NixOS from the start, deployed from the site's own
  # git forge"). Pinned: nixpkgs to nixos-26.05 at 7fc6f2c (20260928; upgraded 20261004 from 1bc55b9 of 20260922,
  # agentvm's revision, by the site agent in the Tender test's stage 4), disko to its release.
  description = "seed site: NixOS hosts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/7fc6f2c20af09cdcaf48b92ec3121860139ec668";
    disko = {
      url = "github:nix-community/disko/v1.13.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # encrypted secrets in the repo (design › Secrets; three recipients, .sops.yaml); no release tags, pinned by commit
    sops-nix = {
      url = "github:Mic92/sops-nix/7214124c20c1542c90deb54af50e2f53ae02711f";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, sops-nix, ... }:
    let system = "x86_64-linux"; in {
      nixosConfigurations = {
        # the agent box (rung 2): Larkbox two
        agent = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ disko.nixosModules.disko sops-nix.nixosModules.sops ./hosts/agent/default.nix ];
          specialArgs = { rescue = self.nixosConfigurations.agent-rescue; };   # its fixed rescue entry (R2.08)
        };
        # TEST FIXTURE, never deployed (site/runbooks/rescue-boot.md, test b): the agent box with its network
        # matched to a MAC it doesn't have, so it boots without 192.168.1.11 and its boot check fails.
        # Installed by root for the next boot only, to prove boot counting falls back by itself.
        agent-test-nonet = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ disko.nixosModules.disko sops-nix.nixosModules.sops ./hosts/agent/default.nix
            ({ lib, ... }: { systemd.network.networks."10-lan".matchConfig.MACAddress = lib.mkForce "02:00:00:00:00:01"; }) ];
          specialArgs = { rescue = self.nixosConfigurations.agent-rescue; };
        };
        # the agent box's rescue system: RAM-booted, installed on its ESP from a pin (rescue.nix, rescue-pin.nix)
        agent-rescue = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ ./rescue.nix ];
        };
        # site2, the second site (rung 5 › E): a VM elsewhere, on the tailnet only; built on itself by
        # tools/site2-deploy.sh
        site2 = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ sops-nix.nixosModules.sops ./hosts/site2/default.nix ];
        };
        # the sandbox VM on infra (R1.92): tracks main, nothing of production
        sandbox = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ ./hosts/sandbox/default.nix ];
        };
        # a keyed installer image: boots with sshd and the builder's key, nothing else
        installer = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            ./installer.nix
          ];
          specialArgs = { inherit disko; };
        };
      };
    };
}

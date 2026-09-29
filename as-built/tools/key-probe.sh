#!/usr/bin/env bash
# key-probe.sh <pubkey-file>: does any site login accept this public key? Asks each sshd with the
# SSH publickey query (nmap's ssh-publickey-acceptance), so no private key is needed. Run with
# `nix-shell -p nmap --run "tools/key-probe.sh key.pub"`. Written for laptop's retirement (20260927).
set -eu; key=$(realpath "$1")
while read host port users; do for u in ${users//,/ }; do
  r=$(nmap -Pn -p $port --script ssh-publickey-acceptance --script-args "ssh.usernames={'$u'},publickeys={'$key'}" $host 2>&1 | grep -E 'Key .* accepted|Accepted|ssh-publickey-acceptance' | tr -s ' ' | tr '\n' ' ')
  printf '%-16s %-5s %-8s %s\n' $host $port $u "${r:-no key accepted}"
done; done <<T
192.168.1.10 22 root
192.168.1.1 22 root
192.168.1.12 22 root,admin,seed-deploy,pi
192.168.1.11 22 admin,agent,root
192.168.1.13 22 admin,agent,root
192.168.1.20 22 seed
git.seed.example.com 2222 git
192.168.1.128 22 root,admin,nixos
T

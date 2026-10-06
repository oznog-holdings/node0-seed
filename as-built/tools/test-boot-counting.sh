#!/usr/bin/env bash
# Tests seed-arm-boot-counting (nixos/modules/boot-assessment.nix) on a scratch /boot, never the real one.
# Case 1 is the failure of 20260930 11:00Z: /boot/loader/seed-blessed listed generations whose entries the builder
# had garbage-collected; the script died under pipefail and every switch failed at "installing bootloader".
set -euo pipefail
cd "$(dirname "$0")/../nixos"
S=$(nix build --no-link --print-out-paths .#nixosConfigurations.agent.config.system.build.seedArmBootCounting)
fail=0; ok() { echo "ok:   $1"; }; bad() { echo "FAIL: $1"; fail=1; }
mk() {  # a scratch /boot: entries for the given generations, loader.conf choosing the newest
  T=$(mktemp -d); mkdir -p $T/loader/entries
  for g in "$@"; do echo "title NixOS $g" > $T/loader/entries/nixos-generation-$g.conf; done
  printf 'timeout 5\ndefault nixos-generation-%s.conf\n' "${@: -1}" > $T/loader/loader.conf
}
run() { SEED_BOOT_ROOT=$T "$S"; }

# 1. blessed 6 and 8 gone (garbage-collected), 9..28 present, 27 blessed, 28 just built
mk $(seq 9 28)
printf 'nixos-generation-6.conf 1\nnixos-generation-8.conf 2\nnixos-generation-27.conf 3\n' > $T/loader/seed-blessed
printf 'nixos-generation-6.conf\nnixos-generation-8.conf\nnixos-generation-27.conf\n' > $T/loader/seed-armed
if out=$(run 2>&1); then ok "case 1 exits 0"; else bad "case 1 exits $?: $out"; fi
grep -qx 'default nixos-generation-27.conf' $T/loader/loader.conf && ok "case 1 default = the last good (27)" || bad "case 1 default: $(grep ^default $T/loader/loader.conf)"
grep -qx 'preferred nixos-generation-28.conf' $T/loader/loader.conf && ok "case 1 preferred = the new one (28)" || bad "case 1 preferred"
[ -e $T/loader/entries/nixos-generation-28+3.conf ] && ok "case 1 28 armed with 3 tries" || bad "case 1 28 not armed"
[ "$(cut -d' ' -f1 $T/loader/seed-blessed)" = nixos-generation-27.conf ] && ok "case 1 record pruned to 27" || bad "case 1 record: $(cat $T/loader/seed-blessed)"
[ $(ls $T/loader/entries | wc -l) = 20 ] && ok "case 1 no entry lost (20)" || bad "case 1 entries: $(ls $T/loader/entries | wc -l)"
rm -rf $T

# 2. every blessed entry gone: the newest plain entry becomes the default, said so; exits 0
mk 9 10 11
printf 'nixos-generation-6.conf 1\n' > $T/loader/seed-blessed; : > $T/loader/seed-armed
if out=$(run 2>&1); then ok "case 2 exits 0"; else bad "case 2 exits $?: $out"; fi
grep -q 'unproven' <<<"$out" && ok "case 2 says the default is unproven" || bad "case 2 output: $out"
[ ! -s $T/loader/seed-blessed ] && ok "case 2 record emptied" || bad "case 2 record: $(cat $T/loader/seed-blessed)"
rm -rf $T

# 3. the ordinary switch: nothing gone, the last good stays default
mk 27 28 29
printf 'nixos-generation-28.conf 1\n' > $T/loader/seed-blessed; printf 'nixos-generation-28.conf\n' > $T/loader/seed-armed
if out=$(run 2>&1); then ok "case 3 exits 0"; else bad "case 3 exits $?: $out"; fi
grep -qx 'default nixos-generation-28.conf' $T/loader/loader.conf && ok "case 3 default 28" || bad "case 3 default"
rm -rf $T
exit $fail

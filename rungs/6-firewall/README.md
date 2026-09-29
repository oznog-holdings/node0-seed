# Rung 6: a dedicated firewall

**In plain terms.** A dedicated firewall, the kind small businesses use, guards the edge of
your network, with rules you can read, back up and check, and the router from rung 5 becomes
your wifi access point behind it. It is the step for a household or small office that wants
the network itself to be as trustworthy as the boxes on it.

**Status.** Designed; not yet built on the bench.

## What you get

- **A firewall at the edge** in place of the [rung 5](../5-edge/) router, with rules you can
  read, back up and check.
- **The rung 5 router as the wifi access point** behind the firewall, still carrying the
  main, guest and IoT networks, and still configured to route, as the way back.

**Buy.** An N100 mini PC with two or more network ports running OPNsense (about $240; the
bench's N100 boxes are among the cheapest with several ports), or a purpose-built firewall
appliance ($890).

**What still fails.** The switch, the UPS and the infra box are still single, and the
firewall is now on every path in and out. That is why the router, now the access point, keeps
its routing configuration ready as the way back.

This rung follows rung 5.

## Decisions and options

**The rung 5 router becomes the access point, and stays the way back.** The firewall takes
over routing, DHCP and the rules between networks; the router switches to access-point duty
behind it and keeps serving the three wifi networks. Its routing configuration stays in the
repository, so putting it back at the edge is one change.

**Guest and IoT separation moves to the firewall.** At rung 5 the router kept guest and IoT
apart itself. Behind a firewall it cannot, so the link from the access point to the firewall
carries each wifi network on its own VLAN (a tag that keeps traffic apart on one cable), and
the firewall applies the same rules: guest and IoT reach only the internet, and your own
devices may open connections into IoT. Designed, not yet built.

**Install at the console, with a fixed upstream address.** The firewall installs from a USB
stick at its keyboard. Give it a fixed address on its upstream side.

**The firewall shares the switch's power.** It now carries every path in and out, so put it
on the same power as the switch, and check that it starts by itself after a power cut.

**Check reachability before and after.** From each network segment, check what it can and
cannot reach, once before the change and once after.

## Costs and measurements

Estimated from the Seed's design prices (US, checked 20260920; [costs](../../costs.md)): $240 lean (rechecked 20260928) and $890 full. Through
rung 6: $4,680 lean and $12,510 full.

No measurements yet.

## Runbooks

Not yet written; they come when the rung is built.

## Configuration

Not yet written; it comes when the rung is built.

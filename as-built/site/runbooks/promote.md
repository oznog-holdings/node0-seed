# Promoting a change to the boxes (from 20260924)

design › Deploying: "Track a deploy ref rather than main. Promotion is one push after the
change is read". The owner made that push a merge (20260924): the forge's `deploy` branch
takes **no direct pushes**, only pull requests merged by the `deployers` team (the person
and the agents), and only when the required status `seed/build-check` is green on the exact
commit. A second agent will review later (required approvals: 0 today).

1. Commit to `main` and push to the forge.
2. Open a pull request `main` → `deploy` (web UI or `POST /repos/seed/seed-lab/pulls`).
3. Within about 5 minutes the agent box's `seed-pr-check` posts `pending`, builds every
   host's closure from that commit and checks core's tree, then posts `success` or
   `failure` (`sudo systemctl start seed-pr-check` runs it at once).
4. On success, merge with style **fast-forward-only** (the repository's default), so
   `deploy` is exactly the checked commit of `main`.
5. The boxes pull `deploy` within 15 minutes (`sudo systemctl start seed-deploy` on each).

A revert is the same path: revert on `main`, pull request, merge. The ruleset applies to
admins as well. `seed-buildcheck` (the status poster) can't merge; it is in the
`build-check` team, not `deployers`.

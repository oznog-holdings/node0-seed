#!/usr/bin/env python3
"""Ask B2 what a key can do (b2_authorize_account, API v4: the site's keys answer 400 on v2
and v3, finding F-B2V4), printing only non-secret facts.
Key id and key come from $B2_KEY_ID / $B2_APP_KEY (fetched by reference); never printed."""
import os, json, requests
r = requests.get("https://api.backblazeb2.com/b2api/v4/b2_authorize_account",
                 auth=(os.environ["B2_KEY_ID"], os.environ["B2_APP_KEY"]), timeout=30)
r.raise_for_status(); d = r.json()
al = d["apiInfo"]["storageApi"]["allowed"]; caps = sorted(al["capabilities"])
print(json.dumps({"capabilities": caps, "buckets": [b.get("name") for b in al.get("buckets") or []],
                  "namePrefix": al.get("namePrefix"), "s3ApiUrl": d["apiInfo"]["storageApi"].get("s3ApiUrl"),
                  "has_deleteFiles": "deleteFiles" in caps,
                  "has_write": any(c in caps for c in ("writeFiles", "shareFiles")),
                  "has_writeBucketSettings": any(c.startswith("writeBucket") for c in caps),
                  "has_key_admin": any(c in caps for c in ("listKeys", "writeKeys", "deleteKeys"))}, indent=1))

#!/usr/bin/env python3
"""R0.06 probe with the writer key ($B2_KEY_ID/$B2_APP_KEY, never printed), B2 native API v4:
upload a small test file, try to permanently delete its version (must be refused), hide it (must succeed),
and list file versions under restic's locks/ prefix. Prints only non-secret facts."""
import os, json, hashlib, requests, datetime
k, s = os.environ["B2_KEY_ID"], os.environ["B2_APP_KEY"]
a = requests.get("https://api.backblazeb2.com/b2api/v4/b2_authorize_account", auth=(k, s), timeout=30).json()
api, tok = a["apiInfo"]["storageApi"]["apiUrl"], a["authorizationToken"]
H = {"Authorization": tok}
bk = a["apiInfo"]["storageApi"]["allowed"]["buckets"][0]; bid, bname = bk["id"], bk["name"]
call = lambda ep, body: requests.post(f"{api}/b2api/v4/{ep}", headers=H, json=body, timeout=30)
name = "probes/r0.06-delete-probe-" + datetime.datetime.now().strftime("%Y%m%dT%H%M%S") + ".txt"
data = b"synthetic probe for R0.06: the writer key must not permanently delete\n"
u = call("b2_get_upload_url", {"bucketId": bid}).json()
up = requests.post(u["uploadUrl"], headers={"Authorization": u["authorizationToken"], "X-Bz-File-Name": name,
     "Content-Type": "text/plain", "X-Bz-Content-Sha1": hashlib.sha1(data).hexdigest()}, data=data, timeout=30)
fid = up.json()["fileId"]; print("upload:", up.status_code, name)
d = call("b2_delete_file_version", {"fileName": name, "fileId": fid})
print("delete_file_version (must be refused):", d.status_code, d.json().get("code"), d.json().get("message", "")[:90])
h = call("b2_hide_file", {"bucketId": bid, "fileName": name})
print("hide_file (must succeed):", h.status_code, h.json().get("action"))
v = call("b2_list_file_versions", {"bucketId": bid, "prefix": name}).json()
print("versions of probe:", [(f["action"], f["uploadTimestamp"]) for f in v["files"]])
lv = call("b2_list_file_versions", {"bucketId": bid, "prefix": "restic/laptop/locks/", "maxFileCount": 50}).json()
print("restic/laptop/locks/ versions:", [(f["fileName"].split("/")[-1][:12], f["action"]) for f in lv["files"]])
lc = call("b2_list_buckets", {"accountId": a["accountId"], "bucketName": bname}).json()
print("bucket (as the writer key can see it):", json.dumps([{"name": b["bucketName"], "type": b.get("bucketType"), "lifecycle": b.get("lifecycleRules"), "sse": (b.get("defaultServerSideEncryption") or {}).get("value")} for b in lc.get("buckets", [])]) if "buckets" in lc else lc.get("code"))

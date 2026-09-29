# The router's configuration in the form the drift check compares (rung 5 brief › A; R5.01, R5.03).
# Input: `uci export` text, one package or many (a live export, the device-config export's uci part,
# or the files in site/router/config/). Output: one line per option, "<package>\t<line>", with
#  - the lab's sections left out: network's interfaces 'wan' and 'wan6' (the internet side), and
#    every firewall section whose name starts with "fixture:" (ANNEX › The bench);
#  - comments (the repository's "lab-owned" markers) and blank lines left out;
#  - secret-named options redacted exactly as /usr/libexec/seed-config-export does on the router,
#    so a live export, the redacted daily export and the repository's placeholders compare equal.
# Sort the output with `sort -s -t "	" -k1,1` to compare packages regardless of export order.
# POSIX awk: it runs on infra (gawk, no python) and on the agent box.
function flush() { if (!lab) printf "%s", buf; buf = ""; lab = 0 }
/^package / { flush(); pkg = $2; gsub(/'/, "", pkg); next }
/^config / {
  flush()
  if (pkg == "network" && ($0 == "config interface 'wan'" || $0 == "config interface 'wan6'")) lab = 1
}
pkg == "firewall" && /^[ \t]*option name 'fixture:/ { lab = 1 }
/^[ \t]*#/ || /^[ \t]*$/ { next }
{
  line = $0
  if (match(line, /^[ \t]*(option|list) (key|password|psk|sae_password|auth_secret|acct_secret|priv_key|private_key|preshared_key|secret|pass|passwd)[ \t]/))
    line = substr(line, 1, RLENGTH - 1) " '<redacted>'"
  buf = buf pkg "\t" line "\n"
}
END { flush() }

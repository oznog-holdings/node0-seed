#!/usr/bin/env python3
"""Print `virsh send-key` commands that type TEXT into a VM console (US layout), one key per call, 120 ms apart
(faster than that dropped and garbled keys on agentvm: see diary 20260923).
Usage: vm-type.py DOMAIN 'text'  | ssh root@infra sh      (a trailing newline is sent as Enter)"""
import sys, shlex
dom, text = sys.argv[1], sys.argv[2] + "\n"
plain = {**{c: "KEY_" + c.upper() for c in "abcdefghijklmnopqrstuvwxyz"}, **{c: "KEY_" + c for c in "0123456789"},
         " ": "KEY_SPACE", "\n": "KEY_ENTER", "-": "KEY_MINUS", "=": "KEY_EQUAL", "[": "KEY_LEFTBRACE", "]": "KEY_RIGHTBRACE",
         ";": "KEY_SEMICOLON", "'": "KEY_APOSTROPHE", "`": "KEY_GRAVE", "\\": "KEY_BACKSLASH", ",": "KEY_COMMA", ".": "KEY_DOT", "/": "KEY_SLASH", "\t": "KEY_TAB"}
shifted = {**{c.upper(): "KEY_" + c.upper() for c in "abcdefghijklmnopqrstuvwxyz"},
           "!": "KEY_1", "@": "KEY_2", "#": "KEY_3", "$": "KEY_4", "%": "KEY_5", "^": "KEY_6", "&": "KEY_7", "*": "KEY_8", "(": "KEY_9", ")": "KEY_0",
           "_": "KEY_MINUS", "+": "KEY_EQUAL", "{": "KEY_LEFTBRACE", "}": "KEY_RIGHTBRACE", ":": "KEY_SEMICOLON", '"': "KEY_APOSTROPHE",
           "~": "KEY_GRAVE", "|": "KEY_BACKSLASH", "<": "KEY_COMMA", ">": "KEY_DOT", "?": "KEY_SLASH"}
# tap each modifier alone first: a lost release earlier left Shift stuck down (diary 20260923)
for m in ("KEY_LEFTSHIFT", "KEY_RIGHTSHIFT", "KEY_LEFTCTRL", "KEY_LEFTALT"):
    print(f"virsh send-key {shlex.quote(dom)} --codeset linux --holdtime 40 {m} >/dev/null; sleep 0.12")
for ch in text:
    if ch in plain: keys = [plain[ch]]
    elif ch in shifted: keys = ["KEY_LEFTSHIFT", shifted[ch]]
    else: sys.exit(f"unsupported char {ch!r}")
    print(f"virsh send-key {shlex.quote(dom)} --codeset linux --holdtime 40 {' '.join(keys)} >/dev/null; sleep 0.12")

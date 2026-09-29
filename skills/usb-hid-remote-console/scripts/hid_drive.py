#!/usr/bin/env python3
"""Drive a USB HID keyboard gadget from a JSON plan — no shell quoting anywhere.

Why this exists: `su -c "<py> hid_keyboard.py type 'some command'"` is re-parsed by Android's
/system/bin/sh, so embedded quotes/spaces split the text and the tail executes locally on the
phone as root. Symptom: `/system/bin/sh: can't create /sys/...` in the phone's output and a
mangled 1-word command typed into the target. Passing the plan as JSON removes the shell from
the path entirely.

Usage (as root):
  su -c "<termux-python> /data/data/com.termux/files/home/hid_drive.py /path/to/plan.json"

Plan = ordered list of steps:
  {"do":"combo","args":["ctrl","alt","f3"],"wait":1.5}
  {"do":"type","text":"sudo systemctl restart gdm","wait":0.4}
  {"do":"enter","wait":0.5}
  {"do":"key","code":"0x28"}
  {"do":"password","file":"<credential-file>","wait":2.5}
  {"do":"poke"}          # abort unless a live host polls the endpoint
  {"do":"sleep","wait":3}

Before sending, validate every planned text against the typer's key map (see below); a silently
skipped character corrupts a blind command.
"""
import glob
import importlib.util
import json
import os
import subprocess
import sys
import time

TYPER = "/data/data/com.termux/files/home/hid_keyboard.py"
spec = importlib.util.spec_from_file_location("hk", TYPER)
hk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hk)          # its __main__ guard keeps import side-effect free


def udc_state():
    return subprocess.run(["/system/bin/cat"] + glob.glob("/sys/class/udc/*/state"),
                          capture_output=True, text=True).stdout.strip()


def poke():
    """All-zero report (no keys). Completes only if a live host polls the endpoint."""
    fd = os.open(hk.HIDG, os.O_WRONLY)
    os.write(fd, b"\x00" * 8)
    os.close(fd)


def validate(plan):
    bad = []
    for i, step in enumerate(plan, 1):
        if step["do"] == "type":
            miss = sorted({c for c in step["text"] if c not in hk.M})
            if miss:
                bad.append((i, miss))
    return bad


def main(plan_path):
    plan = json.load(open(plan_path))
    missing = validate(plan)
    if missing:
        sys.exit("unmapped characters in plan: %s" % missing)
    st = udc_state()
    print("udc state :", st)
    if st != "configured":
        sys.exit("ABORT: host not attached (%s)" % st)
    poke()
    print("host polling: yes (%s)" % hk.HIDG)
    for i, step in enumerate(plan, 1):
        do = step["do"]
        label = {k: v for k, v in step.items() if k != "wait"}
        if do == "combo":
            hk.combo(step["args"])
        elif do == "type":
            hk.type_text(step["text"])
        elif do == "enter":
            hk.press(0x28)
        elif do == "key":
            hk.press(int(step["code"], 0) if isinstance(step["code"], str) else int(step["code"]))
        elif do == "password":
            text = open(step["file"]).read().rstrip("\n")
            hk.type_text(text)                      # value never reaches argv or the log
            label = {"do": "password", "chars": len(text)}
        elif do == "poke":
            poke()
        elif do == "sleep":
            pass
        else:
            sys.exit("unknown step: %s" % do)
        wait = step.get("wait", 0.4)
        print("  step %d: %s (wait %.1fs)" % (i, label, wait), flush=True)
        time.sleep(wait)
    print("plan done")


if __name__ == "__main__":
    main(sys.argv[1])

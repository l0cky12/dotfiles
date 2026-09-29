#!/usr/bin/env python3
"""Audit regressions. All desktop, network, package and firewall commands are fixtures."""
import collections
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HYPR = ROOT / "hypr/.config/hypr"


class AuditTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="dotfiles-audit.")
        self.addCleanup(temporary.cleanup)
        self.tmp = Path(temporary.name)
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, HOME=str(self.tmp), XDG_CACHE_HOME=str(self.tmp / "cache"),
                        XDG_RUNTIME_DIR=str(self.tmp / "runtime"), FIXTURE=str(self.tmp),
                        PATH=f"{self.bin}:{os.environ['PATH']}")

    def stub(self, name, body):
        path = self.bin / name
        path.write_text("#!/usr/bin/env python3\nimport os, sys, json\nfrom pathlib import Path\n"
                        "root = Path(os.environ['FIXTURE'])\n" + body)
        path.chmod(0o755)

    def run_command(self, *args, check=True):
        return subprocess.run(args, env=self.env, text=True, capture_output=True,
                              check=check, timeout=20)

    def test_bindings_have_one_action_per_chord(self):
        lua = shutil.which("lua")
        if not lua:
            self.skipTest("lua is not installed")
        result = self.run_command(lua, str(HYPR / "scripts/keybinds-replay.lua"),
                                  str(HYPR / "conf/keybindings.lua"), str(HYPR))
        rows = json.loads(result.stdout)
        counts = collections.Counter((r["modmask"], r["key"].lower()) for r in rows)
        self.assertEqual([], [key for key, count in counts.items() if count != 1])
        for key in ("XF86AudioRaiseVolume", "XF86AudioLowerVolume", "XF86AudioMute"):
            row = next(r for r in rows if r["key"] == key)
            self.assertTrue(row["arg"].startswith("wpctl "))
            line = next(l for l in (HYPR / "conf/keybindings.lua").read_text().splitlines()
                        if l.startswith(f'exec("{key}"'))
            self.assertIn("locked = true", line)
        legacy = (HYPR / "conf/keybinding.conf").read_text().splitlines()
        for key in ("XF86AudioRaiseVolume", "XF86AudioLowerVolume", "XF86AudioMute"):
            lines = [l for l in legacy if l.startswith("bind") and f", {key}," in l]
            self.assertEqual(1, len(lines))
            self.assertIn("l", lines[0].split(" =")[0][4:])
        close = next(l for l in legacy if l.startswith("bind") and "close all windows" in l)
        self.assertEqual(["CTRL ALT", "Delete", "close all windows", "exec"],
                         [s.strip() for s in close.split("=", 1)[1].split(",")[:4]])

    def test_setup_is_never_a_stow_package(self):
        repo = self.tmp / "repo"
        self.run_command("git", "init", "-q", str(repo))
        for name in ("setup", "hypr"):
            (repo / name).mkdir()
            (repo / name / "file").write_text("fixture\n")
        self.run_command("git", "-C", str(repo), "add", ".")
        self.run_command("git", "-C", str(repo), "-c", "user.name=Fixture", "-c",
                         "user.email=fixture@example.invalid", "commit", "-qm", "fixture")
        self.env.update(DOTS_REPO=str(repo), DOTS_STATE_FILE=str(self.tmp / "state"))
        result = self.run_command(str(ROOT / "dots/.local/bin/dots"), "deploy", "--all", "--dry-run")
        self.assertIn("  - hypr\n", result.stdout)
        self.assertNotIn("  - setup\n", result.stdout)
        self.assertFalse((self.tmp / "state").exists())

    def test_setup_firewall_order_and_grub_preservation(self):
        # The real setup runs with command fixtures and redirected GRUB/home.
        for command in ("pacman", "stow", "yay", "grub-mkconfig"):
            self.stub(command, "sys.exit(0)\n")
        self.stub("iptables", '''
path = root / "rules.json"
rules = json.loads(path.read_text())
op, chain, *rule = sys.argv[1:]
assert chain == "DOCKER-USER"
if op == "-C":
    sys.exit(0 if rule in rules else 1)
elif op == "-D":
    rules.remove(rule)
elif op == "-I":
    index = int(rule.pop(0)) - 1 if rule[0].isdigit() else 0
    rules.insert(index, rule)
elif op == "-A":
    rules.append(rule)
else:
    raise AssertionError(op)
path.write_text(json.dumps(rules))
''')
        rules = self.tmp / "rules.json"
        accept = ["-m", "conntrack", "--ctstate", "RELATED,ESTABLISHED", "-j", "ACCEPT"]
        rules.write_text(json.dumps([accept, ["-j", "RETURN"], ["-j", "DROP"]]))
        grub = self.tmp / "grub"
        original = ('GRUB_CMDLINE_LINUX_DEFAULT="quiet rootflags=subvol=@ cryptdevice=UUID=test:root"\n'
                    'GRUB_DISABLE_OS_PROBER=false\nGRUB_ENABLE_CRYPTODISK=y\n')
        grub.write_text(original)
        cpu = self.tmp / "cpuinfo"
        cpu.write_text("vendor_id : GenuineIntel\n")
        self.env.update(HOME_DIR_OVERRIDE=str(self.tmp), GRUB_FILE=str(grub), CPU_INFO_FILE=str(cpu),
                        TMPDIR=str(self.tmp))
        # Avoid /var/log even when a test runner has permission there.
        source = (ROOT / "setup/arch-dotfiles-setup.sh").read_text()
        source = source.replace("if [[ -w /var/log ]]", "if false")
        source = source.replace('ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)',
                                'ROOT=$AUDIT_REPO')
        self.env["AUDIT_REPO"] = str(ROOT)
        script = self.tmp / "setup.sh"
        script.write_text(source)
        for _ in range(2):
            self.run_command("bash", str(script), "--user", self.run_command("id", "-un").stdout.strip(),
                             "--yes", "--docker-forwarding", "--iommu")
        self.assertEqual([accept, ["-j", "DROP"], ["-j", "RETURN"]], json.loads(rules.read_text()))
        self.assertEqual(original.replace('root"', 'root intel_iommu=on iommu=pt"'), grub.read_text())
        self.assertTrue(list(self.tmp.glob("grub.bak.*")))

        # Bootstrap runs as a different user after a root-owned mktemp. The
        # parent, not just yay/, must be transferred, and passed as an argv.
        (self.bin / "yay").unlink()
        # Force the bootstrap branch even when the host has yay installed.
        script.write_text(source.replace("if command -v yay >/dev/null; then", "if false; then"))
        self.stub("git", "assert sys.argv[1] == 'clone'\nPath(sys.argv[-1]).mkdir()\n")
        self.stub("chown", "(root / 'chowned').write_text(sys.argv[-1])\n")
        self.stub("runuser", '''
build = Path(sys.argv[-1])
assert build.parent == Path((root / "chowned").read_text())
assert sys.argv[-3:] == ['cd -- "$1" && makepkg -si --needed', 'bash', str(build)]
(root / "built").touch()
''')
        self.run_command("bash", str(script), "--user", self.run_command("id", "-un").stdout.strip(), "--yes")
        self.assertTrue((self.tmp / "built").exists())

    def test_wallpaper_rejects_untrusted_preview_paths(self):
        self.stub("getent", "print('104.21.4.33 STREAM fixture')\n")
        self.stub("notify-send", "sys.exit(0)\n")
        self.stub("curl", '''
with (root / "curl-calls").open("a") as stream:
    stream.write(json.dumps(sys.argv[1:]) + "\\n")
output = Path(sys.argv[sys.argv.index("-o") + 1])
output.write_text((root / "response.json").read_text())
''')
        self.env.update(HYPR_WALLPAPER_RUNTIME_DIR=str(self.tmp / "previews"),
                        HYPR_WALLPAPER_DIR=str(self.tmp))
        for entry in ({"id": "../../escaped", "thumbs": {"large": "https://example.invalid/a"}},
                      {"id": "abc123", "thumbs": {"large": "file:///etc/passwd"}}):
            entry["path"] = "https://example.invalid/full.png"
            (self.tmp / "response.json").write_text(json.dumps(
                {"data": [entry], "meta": {"current_page": 1, "last_page": 1}}))
            (self.tmp / "curl-calls").write_text("")
            result = self.run_command(str(ROOT / "hypr/.local/bin/hypr-wallpaper-picker"),
                                      "search", "fixture", "1", check=False)
            self.assertNotEqual(0, result.returncode)
            self.assertIn("invalid response", result.stderr)
            self.assertEqual(1, len((self.tmp / "curl-calls").read_text().splitlines()))
        self.assertFalse((self.tmp / "escaped.jpg").exists())

    def test_spotify_download_failure_does_not_stop_notifications(self):
        self.stub("playerctl", "print('artist|first|album|https://example.invalid/a')\n"
                  "print('artist|second|album|https://example.invalid/b')\n")
        self.stub("curl", "(root / 'curl-args').write_text(json.dumps(sys.argv[1:]))\nsys.exit(28)\n")
        self.stub("notify-send", "with (root / 'notifications').open('a') as stream:\n"
                  "    stream.write(json.dumps(sys.argv[1:]) + '\\n')\n")
        self.run_command(str(HYPR / "scripts/spotify-notify.sh"))
        notifications = (self.tmp / "notifications").read_text().splitlines()
        self.assertEqual(2, len(notifications))
        self.assertNotIn("-i", json.loads(notifications[0]))
        arguments = json.loads((self.tmp / "curl-args").read_text())
        self.assertIn("--max-time", arguments)
        self.assertIn("--connect-timeout", arguments)

    def test_dropdown_waits_for_its_scratchpad_window(self):
        self.stub("sleep", "sys.exit(0)\n")
        self.stub("hyprctl", '''
args = sys.argv[1:]
with (root / "hypr-calls").open("a") as stream:
    stream.write(json.dumps(args) + "\\n")
if args == ["activeworkspace", "-j"]:
    print('{"id":1}')
elif args == ["monitors", "-j"]:
    print('[{"focused":true,"x":0,"y":0,"width":1920,"height":1080,"scale":1,"name":"DP-1"}]')
elif args == ["clients", "-j"]:
    counter = root / "queries"
    n = int(counter.read_text()) + 1 if counter.exists() else 1
    counter.write_text(str(n))
    clients = [{"address":"0xbad","focusHistoryID":5,"workspace":{"name":"1"}}]
    if n >= 4 and not (root / "never-start").exists():
        clients.append({"address":"0xabc","workspace":{"name":"special:scratchpad"}})
    print(json.dumps(clients))
elif args[0] != "dispatch":
    raise AssertionError(args)
''')
        self.run_command(str(HYPR / "scripts/Dropterminal.sh"), "kitty")
        address = self.tmp / "runtime/dropdown_terminal_addr"
        self.assertEqual("0xabc DP-1\n", address.read_text())
        self.assertEqual(0o600, address.stat().st_mode & 0o777)
        self.assertNotIn("address:0xbad", (self.tmp / "hypr-calls").read_text())
        address.unlink()
        (self.tmp / "never-start").touch()
        self.run_command(str(HYPR / "scripts/Dropterminal.sh"), "kitty", check=False)
        self.assertFalse(address.exists())
        self.assertNotIn("address:0xbad", (self.tmp / "hypr-calls").read_text())

    def test_capture_rejects_reused_and_invalid_pids(self):
        runtime = self.tmp / "runtime/hypr-capture"
        runtime.mkdir(parents=True)
        proc = self.tmp / "proc/1234"
        proc.mkdir(parents=True)
        self.env["CAPTURE_PROC_ROOT"] = str(proc.parent)
        self.stub("notify-send", "sys.exit(0)\n")
        record = str(HYPR / "scripts/capture/record.sh")
        for pid in ("1234", "-1", "0", "../1234"):
            (runtime / "record.pid").write_text(pid)
            (proc / "cmdline").write_bytes(b"unrelated-editor\0")
            result = self.run_command(record, "stop", check=False)
            self.assertNotEqual(0, result.returncode)
            self.assertFalse((runtime / "record.pid").exists())
        (runtime / "record.pid").write_text("1234")
        (proc / "cmdline").write_bytes(b"/usr/bin/gpu-screen-recorder\0-w\0DP-1\0")
        self.assertEqual("recording\n", self.run_command(record, "status").stdout)
        self.stub("mpv", "sys.exit(0)\n")
        self.env.update(WEBCAM_DEVICE=str(self.tmp / "video0"),
                        WEBCAM_STARTUP_ATTEMPTS="1", WEBCAM_STARTUP_DELAY="0")
        sleeper = subprocess.Popen(["sleep", "30"])
        try:
            stale = proc.parent / str(sleeper.pid)
            stale.mkdir()
            (stale / "cmdline").write_bytes(b"unrelated-editor\0")
            (runtime / "webcam.pid").write_text(str(sleeper.pid))
            self.run_command(record, "webcam-toggle")
            self.assertIsNone(sleeper.poll(), "webcam stop signaled an unrelated process")
        finally:
            sleeper.terminate()
            sleeper.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()

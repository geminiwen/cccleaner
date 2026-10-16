"""CLI regressions with an isolated HOME and a simulated macOS Keychain."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class KeychainCleanupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix=".keychain-test-", dir=ROOT)
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.home = self.work / "home"
        self.home.mkdir()
        self.config = self.home / ".claude.json"
        self.original = {"projects": {}, "cachedChangelog": "old", "keep": "value"}
        self.config.write_text(json.dumps(self.original))
        (self.home / ".claude").mkdir()
        (self.home / ".claude" / "settings.json").write_text('{"keep": true}')
        self.bin = self.work / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), TMPDIR=str(self.work),
                        MOCK_STATE=str(self.work), MOCK_OS="Darwin",
                        PATH=f"{self.bin}:/opt/homebrew/bin:/usr/bin:/bin")
        self.executable("uname", '#!/bin/sh\nprintf "%s\\n" "$MOCK_OS"\n')
        self.executable("security", """#!/bin/sh
printf '%s|%s|%s\\n' "$1" "$2" "$3" >> "$MOCK_STATE/calls"
case "$1" in list-keychains|dump-keychain) exit 0 ;; esac
[ "$#" -eq 3 ] && [ "$2" = "-s" ] || exit 99
case "$3" in
    'Claude Code-credentials') item=credentials ;;
    'Claude Code-device-keys') item=devices ;;
    *) exit 99 ;;
esac
if [ -n "${MOCK_ERROR:-}" ]; then
    echo sensitive-output-must-not-leak >&2
    exit "$MOCK_ERROR"
fi
count=$(cat "$MOCK_STATE/$item")
[ "$count" -gt 0 ] || exit 44
case "$1" in
    delete-generic-password) echo "$((count - 1))" > "$MOCK_STATE/$item" ;;
    find-generic-password) : ;;
    *) exit 99 ;;
esac
""")
        self.counts(2, 1)
        # A different service must survive every cleanup.
        (self.work / "unrelated").write_text("1")

    def executable(self, name, content):
        path = self.bin / name
        path.write_text(content)
        path.chmod(0o755)

    def counts(self, credentials, devices):
        for name, count in (("credentials", credentials), ("devices", devices)):
            (self.work / name).write_text(str(count))

    def run_cleaner(self, *args):
        result = subprocess.run(["/bin/bash", str(ROOT / "cccleaner"), *args],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual((self.work / "unrelated").read_text(), "1")
        return result

    def test_all_deletes_duplicates_and_preserves_filesystem_backups(self):
        result = self.run_cleaner("--all")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for name in ("credentials", "devices"):
            self.assertEqual((self.work / name).read_text().strip(), "0")
        calls = [line for line in (self.work / "calls").read_text().splitlines()
                 if line.startswith(("delete-generic-password|", "find-generic-password|"))]
        self.assertEqual(len(calls), 6)
        self.assertTrue(all(c.startswith("delete-generic-password|-s|Claude Code-")
                            for c in calls))
        backups = list((self.home / ".claude_backups").glob("claude_.claude.json_*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(json.loads(backups[0].read_text()), self.original)
        self.assertTrue(list((self.home / ".claude_backups").glob("claude_dir_*")))
        self.assertIn("Deep clean completed!", result.stdout)

    def test_already_absent_is_success(self):
        self.counts(0, 0)
        result = self.run_cleaner("--all", "--no-backup")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_access_error_stops_before_json_cleanup_and_hides_output(self):
        self.env["MOCK_ERROR"] = "36"
        result = self.run_cleaner("--all", "--no-backup")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("security exit 36", result.stdout)
        self.assertNotIn("sensitive-output", result.stdout + result.stderr)
        self.assertNotIn("Deep clean completed!", result.stdout)
        self.assertEqual(json.loads(self.config.read_text()), self.original)

    def test_exact_limit_succeeds_with_metadata_only_probe(self):
        self.counts(20, 0)
        result = self.run_cleaner("--all", "--no-backup")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("find-generic-password|-s|Claude Code-credentials",
                      (self.work / "calls").read_text())

    def test_limit_with_remaining_items_fails(self):
        self.counts(21, 0)
        result = self.run_cleaner("--all", "--no-backup")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("items remain", result.stdout)
        self.assertEqual((self.work / "credentials").read_text().strip(), "1")
        self.assertEqual((self.work / "devices").read_text().strip(), "0")
        self.assertNotIn("Deep clean completed!", result.stdout)

    def test_non_macos_does_not_invoke_security(self):
        self.env["MOCK_OS"] = "Linux"
        result = self.run_cleaner("--all", "--no-backup")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.work / "calls").exists())

    def test_missing_security_fails_before_json_cleanup(self):
        (self.bin / "security").unlink()
        for command in ("jq", "mkdir", "date", "cp", "basename"):
            (self.bin / command).symlink_to(shutil.which(command))
        self.env["PATH"] = str(self.bin)
        result = self.run_cleaner("--all")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("security command is required", result.stdout)
        self.assertEqual(json.loads(self.config.read_text()), self.original)

    def test_targeted_and_readonly_options_do_not_invoke_security(self):
        for option in ("--cache", "--folders", "--user-id", "--help", "--list"):
            with self.subTest(option=option):
                result = self.run_cleaner(option, "--no-backup")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertFalse((self.work / "calls").exists())

    def test_interactive_all_also_cleans_keychain(self):
        self.config.write_text('{"projects":{"/example":{"history":[]}}}')
        result = subprocess.run(
            ["/bin/bash", str(ROOT / "cccleaner"), "--interactive", "--no-backup"],
            input="a\ny\n", env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.work / "credentials").read_text().strip(), "0")


if __name__ == "__main__":
    unittest.main()

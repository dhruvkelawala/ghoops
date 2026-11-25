import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("publish_scan.py")


class PublishScanTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.needles = self.root / "needles"
        self.needles.write_text("synthetic-alpha\nsynthetic-bravo\n", encoding="utf-8")
        self.needles.chmod(0o600)
        self.target = self.root / "target"
        self.target.mkdir()

    def scan(self, target, env=None):
        return subprocess.run(
            [sys.executable, "-I", SCRIPT, self.needles, target],
            text=True, capture_output=True, env=env,
        )

    def report(self, result, exit_code):
        self.assertEqual(result.returncode, exit_code, result.stderr)
        self.assertEqual(result.stderr, "")
        return json.loads(result.stdout)

    def test_directory_reports_counts_and_withholds_matching_paths(self):
        (self.target / "notes.txt").write_bytes(b"synthetic-bravo synthetic-bravo\0")
        (self.target / "synthetic-alpha.txt").write_bytes(b"synthetic-bravo")
        shapes = (
            b"ghealth://pair?" b"v=1&token=fixture",
            b"ya29." b"synthetic",
            b"1//" b"synthetic",
            b"GOCSPX-" b"synthetic",
            b"fixture-123" b".apps.googleusercontent.com",
        )
        (self.target / "examples.txt").write_bytes(b"\n".join(shapes))

        result = self.scan(self.target)
        report = self.report(result, 1)
        self.assertEqual(report["paths_hit"], 3)
        self.assertEqual(report["needle_lines"], [1, 2])
        self.assertIn({"path": "notes.txt", "needle_line": 2, "count": 2}, report["hits"])
        self.assertIn({"path": None, "needle_line": 1, "count": 1}, report["hits"])
        self.assertIn({"path": None, "needle_line": 2, "count": 1}, report["hits"])
        self.assertEqual(
            {row["shape"] for row in report["hits"] if row["path"] == "examples.txt"},
            {"pairing link", "Google access token", "Google refresh token",
             "Google client secret", "Google client ID"},
        )
        for value in (b"synthetic-alpha", b"synthetic-bravo", *shapes):
            self.assertNotIn(value.decode("ascii"), result.stdout + result.stderr)

    def test_scan_of_one_file_ignores_its_siblings(self):
        (self.target / "match.txt").write_bytes(b"synthetic-alpha")
        clean = self.target / "clean.txt"
        clean.write_bytes(b"fixture only")
        self.assertEqual(self.report(self.scan(clean), 0)["hits"], [])

    def test_reports_ghoops_bearer_shape_without_printing_the_value(self):
        value = b"ghv3_" + b"X" * 43
        longer_value = b"ghv2_" + b"Y" * 44
        path = self.target / "notes.txt"
        path.write_bytes(b"\n".join([value, longer_value]))
        result = self.scan(path)
        report = self.report(result, 1)
        self.assertEqual(report["hits"], [
            {"path": "notes.txt", "shape": "ghoops bearer", "count": 1},
        ])
        self.assertFalse(value.decode("ascii") in result.stdout)

    def test_reports_ghoops_pairing_code_shape_without_printing_the_line(self):
        code = b"B" * 43
        path = self.target / "notes.txt"
        path.write_bytes(b"GHOOPS1 https://mac-a.invalid:18780 " + code + b"\n")
        result = self.scan(path)
        report = self.report(result, 1)
        self.assertEqual(report["hits"], [
            {"path": "notes.txt", "shape": "ghoops pairing code", "count": 1},
        ])
        self.assertFalse(code.decode("ascii") in result.stdout)

    def test_fixture_values_are_allowed_but_a_different_bearer_is_reported(self):
        examples = (
            b'ghv2_' b'SYNTHETICSYNTHETICSYNTHETICSYNTHETICSYNTHET',
            b'ghv2_' b'synthetic_00000000000000000000000000000000000',
        )
        path = self.target / "notes.txt"
        path.write_bytes(b"\n".join(examples))
        self.assertEqual(self.report(self.scan(path), 0)["hits"], [])

        altered = examples[0][:-1] + (b"A" if examples[0][-1:] != b"A" else b"B")
        path.write_bytes(b"\n".join([*examples, altered]))
        self.assertEqual(self.report(self.scan(path), 1)["hits"], [
            {"path": "notes.txt", "shape": "ghoops bearer", "count": 1},
        ])

    def test_refuses_short_needles_without_echoing_them(self):
        self.needles.write_text("synthetic-alpha\nznq7x\n", encoding="utf-8")
        result = self.scan(self.target)
        self.assertEqual(result.returncode, 2)
        self.assertIn("Needle line 2", result.stderr)
        self.assertNotIn("znq7x", result.stdout + result.stderr)

    def test_history_includes_old_files_other_branches_and_commit_metadata(self):
        env = {name: value for name, value in os.environ.items() if not name.startswith("GIT_")}
        env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")

        def git(*args):
            return subprocess.check_output(
                ["git", "-C", self.target, "-c", "user.name=Synthetic Example",
                 "-c", "user.email=fixture@example.invalid", *args],
                env=env, stderr=subprocess.PIPE, text=True,
            )

        git("init", "-q", "--template=", "-b", "main")
        self.assertTrue(os.path.samefile(git("rev-parse", "--show-toplevel").strip(), self.target))
        (self.target / "old.txt").write_bytes(b"synthetic-alpha")
        git("add", "old.txt")
        git("commit", "-m", "Add an old file")
        git("rm", "old.txt")
        git("commit", "-m", "Delete the old file")
        git("switch", "-c", "side")
        git("commit", "--allow-empty", "-m", "synthetic-bravo")
        git("switch", "main")
        (self.target / "untracked.txt").write_bytes(b"synthetic-alpha")

        result = self.scan(self.target, env={**env, "GIT_DIR": str(self.root / "wrong.git")})
        report = self.report(result, 1)
        self.assertEqual(report["commits_hit"], 2)
        self.assertEqual(report["paths_hit"], 1)
        self.assertEqual(report["needle_lines"], [1, 2])
        self.assertCountEqual(report["hits"], [
            {"path": None, "source": "commit metadata", "needle_line": 2, "count": 1},
            {"path": "old.txt", "needle_line": 1, "count": 1},
        ])
        for value in ("synthetic-alpha", "synthetic-bravo"):
            self.assertNotIn(value, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()

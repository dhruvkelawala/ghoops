import os
from pathlib import Path
import subprocess
import tempfile
import unittest


HOOK = Path(__file__).with_name("pre-push.sh")


class PrePushTest(unittest.TestCase):
    def test_core_tests_run_for_fixture_and_ios_changes(self):
        env = dict(os.environ)
        for name in subprocess.check_output(
            ["git", "rev-parse", "--local-env-vars"], text=True
        ).splitlines():
            env.pop(name, None)
        env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")

        for path in ("fixtures/v2/snapshot.json", "fixtures/v2/README.md", "ios/Model.swift"):
            with self.subTest(path=path), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)

                def git(*args):
                    subprocess.run(
                        ["git", "-c", "user.name=Synthetic Example",
                         "-c", "user.email=fixture@example.invalid", *args],
                        cwd=root, env=env, check=True, capture_output=True,
                    )

                git("init", "-q", "--template=", "-b", "main")
                (root / "Makefile").write_text(
                    "check:\n\t@echo ran-check\nios-core-test:\n\t@echo ran-ios-core-test\n",
                    encoding="utf-8",
                )
                git("add", "Makefile")
                git("commit", "-qm", "Base")
                git("update-ref", "refs/remotes/origin/main", "HEAD")

                changed = root / path
                changed.parent.mkdir(parents=True)
                changed.touch()
                git("add", path)
                git("commit", "-qm", "Change one file")

                result = subprocess.run(
                    ["sh", HOOK], cwd=root, env=env, text=True, capture_output=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(
                    [line for line in result.stdout.splitlines() if line.startswith("ran-")],
                    ["ran-check", "ran-ios-core-test"],
                )


if __name__ == "__main__":
    unittest.main()

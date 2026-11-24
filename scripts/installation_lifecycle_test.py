"""Transaction tests use isolated files and fake process/Keychain boundaries."""
import os
import ast
import importlib
import sys
import subprocess
import signal
import pathlib
import tempfile
import unittest
from unittest.mock import patch
import installation_lifecycle as lifecycle
from signing_contract_test import FakeBuild


class FakeProbe(FakeBuild):
    def __init__(self, target, *, fail_action=None):
        super().__init__(target)
        self.item = None
        self.events = []
        self.fail_action = fail_action
        self.failed = False
        self.on_action = lambda action: None

    def __call__(self, args, **kwargs):
        if "internal-keychain-probe" not in args:
            return super().__call__(args, **kwargs)
        if pathlib.Path(args[0]) != self.target:
            return subprocess.CompletedProcess(args, 1, "", "Keychain requires the installed executable")
        action, service = args[-2:]
        value = kwargs["input"]
        self.events.append((pathlib.Path(args[0]), action, service))
        self.on_action(action)
        if action == "absent":
            okay = self.item is None
        elif action == "add":
            okay = self.item is None
            if okay:
                self.item = value
        elif action == "compare":
            okay = self.item == value
        elif action == "delete":
            okay = self.item == value
            if okay:
                self.item = None
        else:
            raise AssertionError(action)
        if action == self.fail_action and not self.failed:
            self.failed = True
            raise lifecycle.subprocess.TimeoutExpired(args, 120)
        return lifecycle.subprocess.CompletedProcess(args, 0 if okay else 1, "", "")


class InstallationLifecycle(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.target = pathlib.Path(self.folder.name) / "ghealth"
        self.target.write_bytes(b"production A")
        self.target.chmod(0o751)
        self.candidate = pathlib.Path(self.folder.name) / "candidate"
        self.candidate.write_bytes(b"build B")
        self.candidate.chmod(0o755)

    def test_production_install_signal_at_commit_restores_A(self):
        original_commit = lifecycle.Installation.commit
        for sig in (signal.SIGTERM, signal.SIGINT):
            with self.subTest(signal=sig):
                self.target.write_bytes(b"production A")
                self.target.chmod(0o751)
                previous = signal.getsignal(sig)

                def cancel_before_commit(owner):
                    os.kill(os.getpid(), sig)
                    return original_commit(owner)

                with patch.object(lifecycle.Installation, "commit", cancel_before_commit):
                    with self.assertRaisesRegex(RuntimeError, "terminated by signal"):
                        lifecycle.production_install(self.target, self.target.parent, "Synthetic",
                                                     runner=FakeBuild(self.target))
                self.assertEqual(self.target.read_bytes(), b"production A")
                self.assertFalse((self.target.parent / "ghoops").is_symlink())
                self.assertEqual(self.target.stat().st_mode & 0o777, 0o751)
                self.assertFalse(list(self.target.parent.glob(".ghealth-install-*")))
                self.assertEqual(signal.getsignal(sig), previous)
                with lifecycle.Installation(self.target):
                    pass

    def test_production_install_signal_after_commit_checkpoint_restores_A(self):
        original_checkpoint = lifecycle.ControlledTermination.checkpoint
        commit_code = lifecycle.Installation.commit.__code__
        for sig in (signal.SIGTERM, signal.SIGINT):
            with self.subTest(signal=sig):
                self.target.write_bytes(b"production A")
                self.target.chmod(0o751)
                previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, set())
                sent = False

                def cancel_after_checkpoint(termination):
                    nonlocal sent
                    original_checkpoint(termination)
                    if sys._getframe(1).f_code is commit_code:
                        sent = True
                        os.kill(os.getpid(), sig)

                with patch.object(lifecycle.ControlledTermination, "checkpoint", cancel_after_checkpoint):
                    with self.assertRaisesRegex(RuntimeError, "terminated by signal"):
                        lifecycle.production_install(self.target, self.target.parent, "Synthetic",
                                                     runner=FakeBuild(self.target))
                self.assertTrue(sent, "commit cancellation boundary was not reached")
                self.assertEqual(self.target.read_bytes(), b"production A")
                self.assertEqual(self.target.stat().st_mode & 0o777, 0o751)
                self.assertFalse(list(self.target.parent.glob(".ghealth-install-*")))
                self.assertEqual(signal.pthread_sigmask(signal.SIG_BLOCK, set()), previous_mask)

    def test_production_install_signal_during_committed_cleanup_reports_success(self):
        original_rmtree = lifecycle.shutil.rmtree
        for sig in (signal.SIGTERM, signal.SIGINT):
            with self.subTest(signal=sig):
                self.target.write_bytes(b"production A")
                previous = signal.getsignal(sig)
                sent = False

                def cancel_after_cleanup(directory, *args, **kwargs):
                    nonlocal sent
                    result = original_rmtree(directory, *args, **kwargs)
                    if pathlib.Path(directory).name.startswith(".ghealth-install-"):
                        sent = True
                        os.kill(os.getpid(), sig)
                    return result

                with patch.object(lifecycle.shutil, "rmtree", cancel_after_cleanup):
                    try:
                        result = lifecycle.production_install(self.target, self.target.parent, "Synthetic",
                                                              runner=FakeBuild(self.target))
                    except RuntimeError as error:
                        self.fail("committed installation incorrectly reported failure: " + str(error))
                self.assertTrue(sent, "committed cleanup was not reached")
                self.assertEqual(result, "")
                self.assertEqual(self.target.read_bytes(), b"build B")
                self.assertEqual(self.target.stat().st_mode & 0o777, 0o755)
                self.assertFalse(list(self.target.parent.glob(".ghealth-install-*")))
                self.assertEqual(signal.getsignal(sig), previous)
                with lifecycle.Installation(self.target):
                    pass

    def test_production_install_signal_after_last_subprocess_restores_A(self):
        original_run = lifecycle.run
        for sig in (signal.SIGTERM, signal.SIGINT):
            with self.subTest(signal=sig):
                self.target.write_bytes(b"production A")
                self.target.chmod(0o751)
                sent = False

                def cancel_after_run(args, **kwargs):
                    nonlocal sent
                    result = original_run(args, **kwargs)
                    if args[-2:] == ["version", "--json"]:
                        sent = True
                        os.kill(os.getpid(), sig)
                    return result

                with patch.object(lifecycle, "run", cancel_after_run):
                    with self.assertRaisesRegex(RuntimeError, "terminated by signal"):
                        lifecycle.production_install(self.target, self.target.parent, "Synthetic",
                                                     runner=FakeBuild(self.target))
                self.assertTrue(sent, "last subprocess checkpoint was not reached")
                self.assertEqual(self.target.read_bytes(), b"production A")
                self.assertEqual(self.target.stat().st_mode & 0o777, 0o751)
                self.assertFalse(list(self.target.parent.glob(".ghealth-install-*")))

    def test_production_install_signal_after_commit_snapshot_reports_success(self):
        original_sigpending = signal.sigpending
        for sig in (signal.SIGTERM, signal.SIGINT):
            with self.subTest(signal=sig):
                self.target.write_bytes(b"production A")
                previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, set())
                previous_handler = signal.getsignal(sig)
                sent = False

                def cancel_after_snapshot():
                    nonlocal sent
                    mask = signal.pthread_sigmask(signal.SIG_BLOCK, set())
                    self.assertTrue({signal.SIGTERM, signal.SIGINT}.issubset(mask))
                    snapshot = original_sigpending()
                    sent = True
                    os.kill(os.getpid(), sig)
                    return snapshot

                with patch.object(lifecycle.signal, "sigpending", cancel_after_snapshot):
                    result = lifecycle.production_install(self.target, self.target.parent, "Synthetic",
                                                          runner=FakeBuild(self.target))
                self.assertTrue(sent, "commit snapshot was not reached")
                self.assertEqual(result, "")
                self.assertEqual(self.target.read_bytes(), b"build B")
                self.assertFalse(list(self.target.parent.glob(".ghealth-install-*")))
                self.assertEqual(signal.pthread_sigmask(signal.SIG_BLOCK, set()), previous_mask)
                self.assertEqual(signal.getsignal(sig), previous_handler)

    def test_exclusive_owner_uses_private_unique_staging(self):
        self.assertTrue(hasattr(lifecycle, "Installation"), "shared installation owner is missing")
        with lifecycle.Installation(self.target) as first:
            self.assertEqual(first.directory.stat().st_mode & 0o777, 0o700)
            self.assertEqual(first.backup.read_bytes(), b"production A")
            with self.assertRaisesRegex(RuntimeError, "installation lock"):
                with lifecycle.Installation(self.target):
                    self.fail("overlapping owner admitted")
            first.replace(self.candidate)
            self.assertEqual(self.target.read_bytes(), b"build B")
            staging = first.directory
        self.assertEqual(self.target.read_bytes(), b"production A")
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o751)
        self.assertFalse(staging.exists())
        with lifecycle.Installation(self.target) as second:
            self.assertNotEqual(second.directory, staging)
            second.replace(self.candidate)
            second.commit()
        self.assertEqual(self.target.read_bytes(), b"build B")
    def test_uncooperative_writer_is_not_overwritten_by_restore(self):
        with self.assertRaisesRegex(RuntimeError, "unexpectedly replaced"):
            with lifecycle.Installation(self.target) as owner:
                directory = owner.directory
                owner.replace(self.candidate)
                other = self.target.with_name("C")
                other.write_bytes(b"concurrent C")
                other.replace(self.target)
        self.assertEqual(self.target.read_bytes(), b"concurrent C")
        self.assertTrue(directory.exists())
        self.assertEqual((directory / "production-backup").read_bytes(), b"production A")
        with lifecycle.Installation(self.target):
            pass

    def test_replaced_lock_inode_denies_mutation(self):
        with self.assertRaisesRegex(RuntimeError, "lock ownership"):
            with lifecycle.Installation(self.target) as owner:
                owner.lock_path.unlink()
                owner.lock_path.write_bytes(b"not the owned lock")
                owner.replace(self.candidate)
        self.assertEqual(self.target.read_bytes(), b"production A")
    def test_restore_failure_keeps_backup_and_reports_recovery_path(self):
        owner = lifecycle.Installation(self.target)
        real_replace = os.replace

        def fail_restoration(source, target):
            if pathlib.Path(source).read_bytes() == b"production A":
                raise OSError("synthetic restore failure")
            return real_replace(source, target)

        with self.assertRaisesRegex(RuntimeError, "recovery state retained") as failure:
            with patch.object(lifecycle.os, "replace", side_effect=fail_restoration), owner:
                owner.replace(self.candidate)
        self.assertEqual(owner.backup.read_bytes(), b"production A")
        self.assertEqual(self.target.read_bytes(), b"build B")
        self.assertIn(str(owner.directory), str(failure.exception))
        self.assertTrue((owner.directory / "recovery.json").exists())
        with lifecycle.Installation(self.target):
            pass
    def test_add_commit_then_timeout_still_cleans_dummy_and_restores_A(self):
        self.assertTrue(hasattr(lifecycle, "cross_build_check"), "cross-build transaction API is missing")
        fake = FakeProbe(self.target, fail_action="add")
        with self.assertRaises(lifecycle.subprocess.TimeoutExpired):
            lifecycle.cross_build_check(self.target, self.target.parent, "Synthetic", runner=fake)
        self.assertIsNone(fake.item)
        self.assertEqual(self.target.read_bytes(), b"production A")
        actions = [event[1] for event in fake.events]
        self.assertEqual(actions, ["absent", "add", "absent", "compare", "delete", "absent"])
    def test_cleanup_delete_commit_then_timeout_is_confirmed_absent(self):
        fake = FakeProbe(self.target, fail_action="delete")
        fake.item = "synthetic dummy"
        try:
            lifecycle.cleanup_probe(self.target, "io.ghealth.probe." + "0" * 32,
                                    "synthetic dummy", runner=fake)
        except lifecycle.subprocess.TimeoutExpired:
            self.fail("cleanup failed despite confirmed absence after ambiguous deletion")
        self.assertIsNone(fake.item)
        self.assertEqual([event[1] for event in fake.events], ["absent", "compare", "delete", "absent"])
    def test_unverifiable_dummy_cleanup_retains_private_recovery_state(self):
        fake = FakeProbe(self.target)

        def substitute_value(action):
            if action == "compare":
                fake.item = "foreign value"

        fake.on_action = substitute_value
        with self.assertRaisesRegex(RuntimeError, "probe cleanup.*recovery state retained") as failure:
            lifecycle.cross_build_check(self.target, self.target.parent, "Synthetic", runner=fake)
        self.assertEqual(fake.item, "foreign value")
        self.assertNotIn("delete", [event[1] for event in fake.events])
        self.assertEqual(self.target.read_bytes(), b"production A")
        directories = list(self.target.parent.glob(".ghealth-install-*"))
        self.assertEqual(len(directories), 1)
        self.assertEqual((directories[0] / "production-backup").read_bytes(), b"production A")
        self.assertTrue((directories[0] / "probe.json").exists())
        self.assertEqual((directories[0] / "probe.json").stat().st_mode & 0o777, 0o600)
        self.assertIn(str(directories[0]), str(failure.exception))
    def test_cross_build_never_executes_a_concurrently_replaced_target(self):
        fake = FakeProbe(self.target)

        def replace_during_compare(action):
            if action == "compare" and self.target.read_bytes() == b"build B":
                other = self.target.with_name("C")
                other.write_bytes(b"concurrent C")
                other.replace(self.target)

        fake.on_action = replace_during_compare
        with self.assertRaisesRegex(RuntimeError, "unexpectedly replaced"):
            lifecycle.cross_build_check(self.target, self.target.parent, "Synthetic", runner=fake)
        self.assertEqual(self.target.read_bytes(), b"concurrent C")
        self.assertIsNotNone(fake.item, "cleanup must remain unverified when the installed executable is unowned")
        self.assertFalse(any(path == self.target and action == "delete" for path, action, _ in fake.events),
                         "unowned target must never perform cleanup")
        self.assertEqual(len(list(self.target.parent.glob(".ghealth-install-*/production-backup"))), 1)
    def test_sigterm_unwinds_through_value_checked_cleanup_and_restore(self):
        fake = FakeProbe(self.target)
        previous = signal.getsignal(signal.SIGTERM)
        sent = False

        def terminate_after_mutation(action):
            nonlocal sent
            if action == "compare" and not sent:
                handler = signal.getsignal(signal.SIGTERM)
                self.assertTrue(callable(handler), "SIGTERM has no controlled unwinding handler")
                sent = True
                handler(signal.SIGTERM, None)

        fake.on_action = terminate_after_mutation
        with self.assertRaisesRegex(RuntimeError, "terminated by signal"):
            lifecycle.cross_build_check(self.target, self.target.parent, "Synthetic", runner=fake)
        self.assertIsNone(fake.item)
        self.assertEqual(self.target.read_bytes(), b"production A")
        self.assertEqual(signal.getsignal(signal.SIGTERM), previous)
        self.assertFalse(list(self.target.parent.glob(".ghealth-install-*")))
    def test_cross_build_cli_is_import_safe_and_uses_same_transaction(self):
        script = pathlib.Path(__file__).with_name("cross_build_keychain_check.py")
        tree = ast.parse(script.read_text())
        self.assertTrue(any(isinstance(node, ast.FunctionDef) and node.name == "main" for node in tree.body),
                        "cross-build CLI needs an import-safe injectable entry point")
        adapter = importlib.import_module("cross_build_keychain_check")
        fake = FakeProbe(self.target)
        with patch.dict(os.environ, {"SIGN_IDENTITY": "Synthetic"}), \
             patch.object(adapter.sys, "platform", "darwin"), patch("builtins.print") as output:
            adapter.main(["--installed", str(self.target)], runner=fake)
        self.assertEqual(self.target.read_bytes(), b"production A")
        self.assertIsNone(fake.item)
        self.assertIn('"cleanup_verified": true', output.call_args.args[0])
    def test_make_signing_gate_runs_both_behavioral_suites(self):
        root = pathlib.Path(__file__).resolve().parent.parent
        shim = self.target.parent / "fake_gate.py"
        log = self.target.parent / "gate.log"
        shim.write_text("import pathlib, sys\n" + f"p = pathlib.Path({str(log)!r})\n"
                        + "with p.open('a') as f: f.write(sys.argv[1] + '\\n')\n")
        env = {name: value for name, value in os.environ.items() if not name.startswith("GIT_")}
        result = subprocess.run(["make", "--no-print-directory", "signing-contract",
                                 f"PYTHON={sys.executable} {shim}"], cwd=root, env=env,
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(log.exists(), "signing gate does not route through configured test interpreter")
        self.assertEqual(log.read_text().splitlines(), ["scripts/signing_contract_test.py", "scripts/installation_lifecycle_test.py"])
    def test_modified_backup_is_never_restored(self):
        with self.assertRaisesRegex(RuntimeError, "backup.*changed"):
            with lifecycle.Installation(self.target) as owner:
                owner.replace(self.candidate)
                owner.backup.write_bytes(b"corrupt backup")
        self.assertEqual(self.target.read_bytes(), b"build B")
        self.assertTrue(owner.directory.exists())
    def test_check_excludes_production_install_until_cleanup_finishes(self):
        fake = FakeProbe(self.target)
        attempts = []

        def competing_install(action):
            competing = FakeBuild(self.target)
            with self.assertRaisesRegex(RuntimeError, "installation lock"):
                lifecycle.production_install(self.target, self.target.parent, "Synthetic", runner=competing)
            self.assertEqual(competing.calls, [], "contender must fail before build or signing")
            attempts.append(action)

        fake.on_action = competing_install
        result = lifecycle.cross_build_check(self.target, self.target.parent, "Synthetic", runner=fake)
        self.assertTrue(result["production_binary_restored"])
        self.assertIn("add", attempts)
        self.assertIn("compare", attempts)
        self.assertEqual(attempts[-1], "absent")
        self.assertEqual(self.target.read_bytes(), b"production A")
        lifecycle.production_install(self.target, self.target.parent, "Synthetic", runner=FakeBuild(self.target))
        self.assertEqual(self.target.read_bytes(), b"build B")

    def test_separate_process_cannot_acquire_owned_installation_lock(self):
        scripts = str(pathlib.Path(__file__).resolve().parent)
        program = (f"import sys; sys.path.insert(0, {scripts!r}); "
                   "from installation_lifecycle import Installation; "
                   f"Installation({str(self.target)!r}).__enter__()")
        with lifecycle.Installation(self.target):
            result = subprocess.run([sys.executable, "-c", program], capture_output=True, text=True, timeout=15)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("installation lock is already owned", result.stderr)
        self.assertEqual(self.target.read_bytes(), b"production A")

    def test_cleanup_absent_is_idempotent_and_never_deletes(self):
        fake = FakeProbe(self.target)
        for _ in range(2):
            lifecycle.cleanup_probe(self.target, "io.ghealth.probe." + "0" * 32, "synthetic dummy", runner=fake)
        self.assertEqual([event[1] for event in fake.events], ["absent", "absent"])
    def test_recovery_record_write_failure_still_reports_retained_backup(self):
        owner = lifecycle.Installation(self.target)
        failure = None
        try:
            with patch.object(owner, "restore", side_effect=OSError("restore failed")), \
                 patch.object(pathlib.Path, "write_text", side_effect=OSError("record write failed")), owner:
                owner.replace(self.candidate)
        except Exception as error:
            failure = error
        self.assertIsInstance(failure, RuntimeError, "record write failure hid the recovery outcome")
        self.assertEqual(owner.backup.read_bytes(), b"production A")
        self.assertIn(str(owner.directory), str(failure))
    def test_add_commits_then_reports_failure_and_cleanup_still_runs(self):
        fake = FakeProbe(self.target)

        def runner(args, **kwargs):
            result = fake(args, **kwargs)
            if "internal-keychain-probe" in args and args[-2] == "add":
                result.returncode = 1
            return result

        with self.assertRaises(RuntimeError):
            lifecycle.cross_build_check(self.target, self.target.parent, "Synthetic", runner=runner)
        self.assertIsNone(fake.item)
        self.assertEqual(self.target.read_bytes(), b"production A")
        self.assertIn("delete", [event[1] for event in fake.events])

    def test_uncommitted_ambiguous_delete_retains_recovery_and_reports_failure(self):
        fake = FakeProbe(self.target)

        def runner(args, **kwargs):
            if "internal-keychain-probe" in args and args[-2] == "delete":
                fake.events.append((pathlib.Path(args[0]), args[-2], args[-1]))
                raise subprocess.TimeoutExpired(args, 120)
            return fake(args, **kwargs)

        with self.assertRaisesRegex(RuntimeError, "probe cleanup.*recovery state retained"):
            lifecycle.cross_build_check(self.target, self.target.parent, "Synthetic", runner=runner)
        self.assertIsNotNone(fake.item)
        self.assertEqual(self.target.read_bytes(), b"production A")
        self.assertEqual(len(list(self.target.parent.glob(".ghealth-install-*/probe.json"))), 1)
    def test_cleanup_uses_owned_installed_executable_not_private_backup(self):
        fake = FakeProbe(self.target)

        def runner(args, **kwargs):
            if "internal-keychain-probe" in args and pathlib.Path(args[0]) != self.target:
                return subprocess.CompletedProcess(args, 1, "", "Keychain requires the installed executable")
            return fake(args, **kwargs)

        try:
            result = lifecycle.cross_build_check(self.target, self.target.parent, "Synthetic", runner=runner)
        except RuntimeError:
            self.fail("cleanup tried to run a private backup that cannot access production Keychain")
        self.assertTrue(result["cleanup_verified"])
        self.assertIsNone(fake.item)
        self.assertEqual(self.target.read_bytes(), b"production A")


if __name__ == "__main__":
    unittest.main()

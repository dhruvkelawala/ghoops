"""Behavioral signing tests. All executables/certificates are synthetic."""
import pathlib
import os
import sys
import signal
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import installation_lifecycle as lifecycle


class SigningInstallContract(unittest.TestCase):
    def test_empty_and_adhoc_identity_are_rejected_without_subprocess(self):
        self.assertIsNotNone(lifecycle, "production signing helper is missing")
        for identity in ("", "-", "   ", " - "):
            with self.subTest(identity=identity), patch("subprocess.run") as runner:
                with self.assertRaisesRegex(ValueError, "certificate signing identity"):
                    lifecycle.validate_identity(identity)
                runner.assert_not_called()


class FakeCodesign:
    def __init__(self, metadata=None, requirement=None, verify_failure=False):
        self.calls = []
        self.metadata = metadata or "Identifier=io.ghealth.cli\nSignature size=1000\nAuthority=Synthetic certificate\n"
        self.requirement = requirement or 'identifier "io.ghealth.cli" and anchor = H"' + "1" * 40 + '"'
        self.verify_failure = verify_failure

    def __call__(self, args, **kwargs):
        self.calls.append(args)
        if "--verify" in args and self.verify_failure:
            return subprocess.CompletedProcess(args, 1, "", "invalid signature")
        extraction = next((arg.split("=", 1)[1] for arg in args if arg.startswith("--extract-certificates=")), None)
        if "--extract-certificates" in args:
            extraction = args[args.index("--extract-certificates") + 1]
        if extraction is not None:
            pathlib.Path(extraction + "0").write_bytes(b"synthetic DER certificate")
        text = self.metadata + "designated => " + self.requirement + "\n" if "--display" in args else ""
        return subprocess.CompletedProcess(args, 0, "", text)


class CertificateVerification(unittest.TestCase):
    def test_verified_candidate_must_have_certificate_backed_cli_identity(self):
        self.assertTrue(hasattr(lifecycle, "sign_candidate"), "sign-and-inspect policy is missing")
        cases = (
            "Identifier=io.ghealth.cli\nSignature=adhoc\n",
            "Identifier=wrong.cli\nSignature size=1000\nAuthority=Synthetic\n",
            "Identifier=io.ghealth.cli\nSignature size=1000\n",
        )
        with tempfile.TemporaryDirectory() as folder:
            candidate = pathlib.Path(folder) / "candidate"
            candidate.write_bytes(b"synthetic executable")
            for metadata in cases:
                with self.subTest(metadata=metadata), self.assertRaisesRegex(RuntimeError, "certificate-backed io.ghealth.cli"):
                    lifecycle.sign_candidate(candidate, "Synthetic", runner=FakeCodesign(metadata))
            fake = FakeCodesign()
            info = lifecycle.sign_candidate(candidate, "Synthetic", runner=fake)
            self.assertEqual(info.requirement, fake.requirement)
            self.assertTrue(any("--verify" in cmd and "--strict" in cmd for cmd in fake.calls))
            self.assertTrue(any("--test-requirement" in cmd and "certificate leaf" in cmd[cmd.index("--test-requirement") + 1] for cmd in fake.calls))
            with self.assertRaises(RuntimeError):
                lifecycle.sign_candidate(candidate, "Synthetic", runner=FakeCodesign(verify_failure=True))
    def test_designated_requirement_must_bind_stable_certificate_cli_identity(self):
        with tempfile.TemporaryDirectory() as folder:
            candidate = pathlib.Path(folder) / "candidate"
            candidate.write_bytes(b"synthetic executable")
            for requirement in ("true", 'identifier "io.ghealth.cli"', 'cdhash H"' + "1" * 40 + '"',
                                'identifier "io.ghealth.cli" or anchor apple generic'):
                with self.subTest(requirement=requirement), self.assertRaisesRegex(RuntimeError, "stable certificate.*requirement"):
                    lifecycle.sign_candidate(candidate, "Synthetic", runner=FakeCodesign(requirement=requirement))
    def test_requirements_use_literal_source_instead_of_filenames(self):
        with tempfile.TemporaryDirectory() as folder:
            candidate = pathlib.Path(folder) / "candidate"
            candidate.write_bytes(b"synthetic executable")
            fake = FakeCodesign()

            def runner(args, **kwargs):
                if "--test-requirement" in args:
                    requirement = args[args.index("--test-requirement") + 1]
                    if not requirement.startswith("="):
                        return subprocess.CompletedProcess(args, 2, "", "requirement treated as filename")
                return fake(args, **kwargs)

            info = lifecycle.sign_candidate(candidate, "Synthetic", runner=runner)
            lifecycle.compatible_requirement(info, info, candidate, runner=runner)
            requirements = [cmd[cmd.index("--test-requirement") + 1] for cmd in fake.calls
                            if "--test-requirement" in cmd]
            self.assertEqual(len(requirements), 2)
            self.assertTrue(all(requirement.startswith("=") for requirement in requirements))

    def test_certificate_extraction_uses_documented_optional_value_syntax(self):
        with tempfile.TemporaryDirectory() as folder:
            candidate = pathlib.Path(folder) / "candidate"
            candidate.write_bytes(b"synthetic executable")
            fake = FakeCodesign()

            def runner(args, **kwargs):
                if "--extract-certificates" in args:
                    return subprocess.CompletedProcess(args, 2, "", "optional values require --name=value")
                return fake(args, **kwargs)

            try:
                lifecycle.sign_candidate(candidate, "Synthetic", runner=runner)
            except RuntimeError:
                self.fail("certificate extraction does not use documented --name=value syntax")


class FakeBuild(FakeCodesign):
    def __init__(self, target, mismatch=False, *, go_version="go1.27.4"):
        super().__init__()
        self.target = target
        self.mismatch = mismatch
        self.go_version = go_version
        self.signed_paths = []

    def __call__(self, args, **kwargs):
        if args[1:] == ["env", "GOVERSION"]:
            self.calls.append(args)
            return subprocess.CompletedProcess(args, 0, self.go_version + "\n", "")
        if "build" in args:
            output = pathlib.Path(args[args.index("-o") + 1])
            output.write_bytes(b"build B")
            output.chmod(0o755)
        if "--sign" in args:
            self.signed_paths.append(pathlib.Path(args[-1]))
        result = super().__call__(args, **kwargs)
        if "--display" in args and self.mismatch and pathlib.Path(args[-1]).name != "production-backup":
            result.stderr = result.stderr.replace("1" * 40, "2" * 40)
        return result


class ProductionInstall(unittest.TestCase):
    def test_old_go_is_rejected_before_building(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            target = root / "ghealth"
            target.write_bytes(b"production A")
            fake = FakeBuild(target, go_version="go1.27.1")
            with self.assertRaisesRegex(RuntimeError, r"Go 1\.27\.4.*found go1\.27\.1"):
                lifecycle.production_install(target, root, "Synthetic", runner=fake)
            self.assertFalse(any(args[1:2] == ["build"] for args in fake.calls))
            self.assertEqual(target.read_bytes(), b"production A")

    def test_requirement_change_is_refused_before_production_replacement(self):
        self.assertTrue(hasattr(lifecycle, "production_install"), "production helper entry point is missing")
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            target = root / "ghealth"
            target.write_bytes(b"production A")
            target.chmod(0o751)
            fake = FakeBuild(target, mismatch=True)
            with self.assertRaisesRegex(RuntimeError, "designated requirement.*migration"):
                lifecycle.production_install(target, root, "Synthetic", runner=fake)
            self.assertEqual(target.read_bytes(), b"production A")
            self.assertTrue(fake.signed_paths)
            self.assertTrue(all(path != target for path in fake.signed_paths))
            fake = FakeBuild(target)
            lifecycle.production_install(target, root, "Synthetic", runner=fake)
            self.assertEqual(target.read_bytes(), b"build B")
            self.assertEqual(target.stat().st_mode & 0o777, 0o755)
            alias = root / "ghoops"
            self.assertTrue(alias.is_symlink(), "new command alias is missing")
            self.assertEqual(alias.readlink(), pathlib.Path("ghealth"))
            self.assertEqual(alias.read_bytes(), b"build B")
            lifecycle.production_install(target, root, "Synthetic", runner=fake)
            self.assertEqual(alias.read_bytes(), b"build B")
            self.assertTrue(all(path.parent.name.startswith(".ghealth-install-") for path in fake.signed_paths))
    def test_install_preserves_an_unrelated_alias_path(self):
        for kind in ("file", "symlink"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as folder:
                root = pathlib.Path(folder)
                target = root / "ghealth"
                target.write_bytes(b"production A")
                alias = root / "ghoops"
                other = root / "other"
                other.write_bytes(b"unrelated command")
                if kind == "file":
                    alias.write_bytes(b"unrelated command")
                else:
                    alias.symlink_to(other.name)
                with self.assertRaisesRegex(RuntimeError, "ghoops.*already exists"):
                    lifecycle.production_install(target, root, "Synthetic", runner=FakeBuild(target))
                self.assertEqual(target.read_bytes(), b"production A")
                self.assertEqual(alias.read_bytes(), b"unrelated command")

    def test_install_sigterm_before_commit_restores_production(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            target = root / "ghealth"
            target.write_bytes(b"production A")
            fake = FakeBuild(target)
            previous = signal.getsignal(signal.SIGTERM)

            def runner(args, **kwargs):
                result = fake(args, **kwargs)
                if "version" in args:
                    handler = signal.getsignal(signal.SIGTERM)
                    self.assertTrue(callable(handler), "install does not control SIGTERM")
                    handler(signal.SIGTERM, None)
                return result

            with self.assertRaisesRegex(RuntimeError, "terminated by signal"):
                lifecycle.production_install(target, root, "Synthetic", runner=runner)
            self.assertEqual(target.read_bytes(), b"production A")
            self.assertEqual(signal.getsignal(signal.SIGTERM), previous)
    def test_install_refuses_to_execute_an_uncooperative_replacement(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            target = root / "ghealth"
            target.write_bytes(b"production A")
            fake = FakeBuild(target)
            replaced = False

            def runner(args, **kwargs):
                nonlocal replaced
                result = fake(args, **kwargs)
                if "--display" in args and pathlib.Path(args[-1]) == target and not replaced:
                    replacement = root / "C"
                    replacement.write_bytes(b"unowned C")
                    replacement.replace(target)
                    replaced = True
                return result

            with self.assertRaisesRegex(RuntimeError, "unexpectedly replaced"):
                lifecycle.production_install(target, root, "Synthetic", runner=runner)
            self.assertEqual(target.read_bytes(), b"unowned C")
            self.assertFalse(any("version" in args for args in fake.calls), "unowned installed binary was executed")


class MakeInstallAdapter(unittest.TestCase):
    def test_make_install_routes_through_behavioral_production_helper(self):
        root = pathlib.Path(__file__).resolve().parent.parent
        self.assertTrue((root / "scripts/production_install.py").exists(), "Makefile production helper adapter is missing")
        with tempfile.TemporaryDirectory() as folder:
            directory = pathlib.Path(folder)
            target = directory / "ghealth"
            target.write_bytes(b"production A")
            shim = directory / "fake_python.py"
            shim.write_text(
                "import sys, pathlib\nsys.platform = 'darwin'\n"
                + f"sys.path.insert(0, {str(root / 'scripts')!r})\n"
                + "from production_install import main\nfrom signing_contract_test import FakeBuild\n"
                + f"assert sys.argv[1] == 'scripts/production_install.py', sys.argv\n"
                + f"main(sys.argv[2:], runner=FakeBuild(pathlib.Path({str(target)!r})))\n"
            )
            command = ["make", "--no-print-directory", "-o", "check", "install",
                       f"PYTHON={sys.executable} {shim}", f"INSTALLED={target}"]
            env = {name: value for name, value in os.environ.items() if not name.startswith("GIT_")}
            result = subprocess.run(command + ["SIGN_IDENTITY=-"], cwd=root, env=env,
                                    capture_output=True, text=True, timeout=15)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(target.read_bytes(), b"production A")
            result = subprocess.run(command + ["SIGN_IDENTITY=Synthetic"], cwd=root, env=env,
                                    capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(target.read_bytes(), b"build B")


if __name__ == "__main__":
    unittest.main()

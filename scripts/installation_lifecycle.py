"""Certificate signing and installation transaction policy for ghoops."""
import fcntl
import hashlib
import json
import os
import pathlib
import re
import secrets
import shutil
import signal
import stat
import subprocess
import tempfile
from dataclasses import dataclass

CODESIGN = "/usr/bin/codesign"
IDENTIFIER = "io.ghealth.cli"


def run(args, *, runner=subprocess.run, **kwargs):
    result = runner([str(arg) for arg in args], capture_output=True, text=True, timeout=120, **kwargs)
    if result.returncode:
        raise RuntimeError("operation failed: " + str(args[0]))
    return result


@dataclass(frozen=True)
class Signature:
    requirement: str


def inspect_signature(path, *, runner=subprocess.run):
    run([CODESIGN, "--verify", "--strict", path], runner=runner)
    with tempfile.TemporaryDirectory(prefix="certificates-", dir=path.parent) as folder:
        prefix = str(pathlib.Path(folder) / "cert-")
        result = run([CODESIGN, "--display", "--verbose=4", "-r-", "--extract-certificates=" + prefix, path], runner=runner)
        lines = (result.stdout + result.stderr).splitlines()
        leaf = pathlib.Path(prefix + "0")
        requirements = [line.removeprefix("designated => ") for line in lines if line.startswith("designated => ")]
        if (f"Identifier={IDENTIFIER}" not in lines or "Signature=adhoc" in lines
                or not any(line.startswith("Authority=") and line[10:].strip() for line in lines)
                or not leaf.is_file() or not leaf.read_bytes() or len(requirements) != 1):
            raise RuntimeError("a certificate-backed io.ghealth.cli signature is required")
        requirement = requirements[0]
        if (not re.search(r'\bidentifier\s+(?:"io\.ghealth\.cli"|io\.ghealth\.cli)(?=\s|$)', requirement)
                or not re.search(r'\b(?:anchor|certificate)\b', requirement)
                or re.search(r'\b(?:cdhash|or|true)\b', requirement)):
            raise RuntimeError("a stable certificate identity designated requirement is required")
        certificate_hash = hashlib.sha1(leaf.read_bytes()).hexdigest()
        run([CODESIGN, "--verify", "--strict", "--test-requirement",
             f'=identifier "{IDENTIFIER}" and certificate leaf = H"{certificate_hash}"', path], runner=runner)
        return Signature(requirements[0])


def sign_candidate(path, identity, *, runner=subprocess.run):
    validate_identity(identity)
    run([CODESIGN, "--force", "--sign", identity, "--identifier", IDENTIFIER, "--timestamp=none", path], runner=runner)
    return inspect_signature(path, runner=runner)


def validate_identity(identity):
    if not identity.strip() or identity.strip() == "-":
        raise ValueError("a certificate signing identity is required; ad-hoc signing is refused")
    return identity


def fingerprint(path):
    try:
        info = path.lstat()
    except FileNotFoundError:
        return None
    if not stat.S_ISREG(info.st_mode):
        raise RuntimeError("installation target must be a regular file, not a symlink")
    return (info.st_dev, info.st_ino, info.st_mode, info.st_size, info.st_mtime_ns,
            hashlib.sha256(path.read_bytes()).hexdigest())


class Installation:
    """Own cooperating installers and retain a private production backup.

    The lock is advisory; observed nonparticipating writes fail ownership checks.
    """
    def __init__(self, target, *, termination=None):
        self.target = pathlib.Path(target)
        self.termination = termination
        self.lock_path = self.target.with_name("." + self.target.name + "-install.lock")
        self.fd = None
        self.committed = False
        self.changed = False
        self.keep_state = False
        self.alias = None

    def __enter__(self):
        self.target.parent.mkdir(parents=True, exist_ok=True)
        self.fd = os.open(self.lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        try:
            fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            os.close(self.fd)
            self.fd = None
            raise RuntimeError("installation lock is already owned") from error
        try:
            self.directory = pathlib.Path(tempfile.mkdtemp(prefix=".ghealth-install-", dir=self.target.parent))
            self.backup = self.directory / "production-backup"
            self.expected = fingerprint(self.target)
            if self.expected is not None:
                shutil.copy2(self.target, self.backup)
            self.backup_snapshot = fingerprint(self.backup)
            if (self.expected is not None and
                    (self.backup_snapshot is None or self.backup_snapshot[2:] != self.expected[2:])):
                raise RuntimeError("production backup does not match the snapshot")
            self.assert_owned()
            return self
        except BaseException:
            if hasattr(self, "directory"):
                shutil.rmtree(self.directory)
            os.close(self.fd)
            self.fd = None
            raise

    def assert_owned(self):
        if self.fd is None:
            raise RuntimeError("installation lock ownership is not active")
        owned = os.fstat(self.fd)
        try:
            current = self.lock_path.lstat()
        except FileNotFoundError as error:
            raise RuntimeError("installation lock ownership was lost") from error
        if (current.st_dev, current.st_ino) != (owned.st_dev, owned.st_ino):
            raise RuntimeError("installation lock ownership was lost")
        if fingerprint(self.target) != self.expected:
            raise RuntimeError("installation target was unexpectedly replaced; refusing to overwrite it")

    def replace(self, source):
        self.assert_owned()
        fd, name = tempfile.mkstemp(prefix="candidate-", dir=self.directory)
        os.close(fd)
        staging = pathlib.Path(name)
        shutil.copy2(source, staging)
        expected = fingerprint(staging)
        self.assert_owned()
        os.replace(staging, self.target)
        self.expected = expected
        self.changed = True
        self.assert_owned()

    def assert_backup(self):
        if fingerprint(self.backup) != self.backup_snapshot:
            raise RuntimeError("production backup unexpectedly changed; refusing to use it")

    def restore(self):
        self.assert_owned()
        self.assert_backup()
        if self.changed:
            if self.backup.exists():
                self.replace(self.backup)
            else:
                self.target.unlink()
                self.expected = None
            self.changed = False

    def link_command(self):
        alias = self.target.with_name("ghoops")
        try:
            alias.symlink_to(self.target.name)
        except FileExistsError:
            if not alias.is_symlink() or alias.resolve() != self.target.resolve():
                raise RuntimeError("ghoops command path already exists: " + str(alias))
        else:
            self.alias = (alias, alias.lstat())

    def commit(self):
        """Commit at the blocked-signal pending snapshot, or restore on cancellation."""
        self.assert_owned()
        if self.termination is None:
            self.committed = True
            return
        previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, self.termination.previous)
        try:
            self.termination.checkpoint()
            pending = signal.sigpending().intersection(self.termination.previous)
            if pending:
                self.termination.receive(min(pending), None)
                self.termination.checkpoint()
            self.committed = True
            self.termination.committed = True
        finally:
            signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)

    def __exit__(self, kind, error, traceback):
        try:
            if not self.committed:
                self.restore()
                if self.alias is not None:
                    alias, created = self.alias
                    current = alias.lstat()
                    if (current.st_dev, current.st_ino) != (created.st_dev, created.st_ino):
                        raise RuntimeError("ghoops alias was unexpectedly replaced")
                    alias.unlink()
            if not self.keep_state:
                shutil.rmtree(self.directory)
        except BaseException as failure:
            try:
                (self.directory / "recovery.json").write_text(json.dumps({
                    "target": str(self.target), "backup": str(self.backup),
                    "expected_target": self.expected, "production_restore_verified": False,
                    "limit": "SIGKILL and power loss require manual recovery",
                }) + "\n")
            except OSError:
                pass
            raise RuntimeError("installation cleanup failed; recovery state retained at " + str(self.directory)
                               + "; " + str(failure)) from failure
        finally:
            os.close(self.fd)
            self.fd = None


def compatible_requirement(previous, candidate, path, *, runner=subprocess.run):
    # Canonical disassembly: developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html
    if previous.requirement != candidate.requirement:
        raise RuntimeError("designated requirement changed; explicit credential migration is required")
    run([CODESIGN, "--verify", "--strict", "--test-requirement", "=" + previous.requirement, path], runner=runner)


def build_candidate(owner, root, identity, *, go="go", ldflags="", runner=subprocess.run):
    candidate = owner.directory / "signed-candidate"
    run([go, "build", "-trimpath", "-ldflags", ldflags, "-o", candidate, "./cmd/ghoops"],
        runner=runner, cwd=root, env={**os.environ, "CGO_ENABLED": "1", "GOTOOLCHAIN": "local"})
    candidate.chmod(0o755)
    signature = sign_candidate(candidate, identity, runner=runner)
    return candidate, signature


def production_install(target, root, identity, *, go="go", ldflags="", runner=subprocess.run):
    validate_identity(identity)
    with ControlledTermination() as termination, Installation(target, termination=termination) as owner:
        runner = termination.wrap(runner)
        previous = inspect_signature(owner.backup, runner=runner) if owner.backup.exists() else None
        candidate, signature = build_candidate(owner, root, identity, go=go, ldflags=ldflags, runner=runner)
        if previous is not None:
            compatible_requirement(previous, signature, candidate, runner=runner)
        owner.replace(candidate)
        installed_signature = inspect_signature(owner.target, runner=runner)
        owner.assert_owned()
        compatible_requirement(signature, installed_signature, owner.target, runner=runner)
        owner.assert_owned()
        result = run([owner.target, "version", "--json"], runner=runner)
        owner.link_command()
        owner.commit()
        return result.stdout


def probe(path, action, service, value, *, runner=subprocess.run):
    run([path, "internal-keychain-probe", action, service], runner=runner, input=value)


def cleanup_probe(path, service, value, *, runner=subprocess.run, ownership_check=None):
    def checked(action):
        if ownership_check is not None:
            ownership_check()
        probe(path, action, service, value, runner=runner)
        if ownership_check is not None:
            ownership_check()

    try:
        checked("absent")
        return
    except (RuntimeError, subprocess.TimeoutExpired):
        pass
    checked("compare")
    try:
        checked("delete")
    except (RuntimeError, subprocess.TimeoutExpired):
        checked("absent")
        return
    checked("absent")


class ControlledTermination:
    """Defer SIGTERM/SIGINT to checkpoints without interrupting cleanup.
    A committed installation reports success despite later handled cancellation.
    """
    def __enter__(self):
        self.pending = None
        self.committed = False
        self.previous = {sig: signal.getsignal(sig) for sig in (signal.SIGTERM, signal.SIGINT)}
        for sig in self.previous:
            signal.signal(sig, self.receive)
        return self

    def receive(self, signum, frame):
        self.pending = signum

    def checkpoint(self):
        if self.pending is not None:
            raise RuntimeError("terminated by signal " + str(self.pending) + "; cleanup completed or reported separately")

    def wrap(self, runner):
        def guarded(*args, **kwargs):
            self.checkpoint()
            result = runner(*args, **kwargs)
            self.checkpoint()
            return result
        return guarded

    def __exit__(self, kind, error, traceback):
        for sig, handler in self.previous.items():
            signal.signal(sig, handler)
        if kind is None and not self.committed:
            self.checkpoint()


def cross_build_check(target, root, identity, *, go="go", runner=subprocess.run):
    validate_identity(identity)
    cleanup_runner = runner
    with ControlledTermination() as termination, Installation(target) as owner:
        runner = termination.wrap(runner)
        if not owner.backup.exists():
            raise RuntimeError("a regular installed ghealth executable is required")
        previous = inspect_signature(owner.backup, runner=runner)
        candidate, signature = build_candidate(owner, root, identity, go=go,
            ldflags="-X main.version=0.1.0-signature-check -X main.revision=signature-probe-b", runner=runner)
        compatible_requirement(previous, signature, candidate, runner=runner)
        if owner.backup.read_bytes() == candidate.read_bytes():
            raise RuntimeError("different executable content with the same designated requirement is required")
        service = "io.ghealth.probe." + secrets.token_hex(16)
        value = secrets.token_hex(32)
        state = owner.directory / "probe.json"
        state.write_text(json.dumps({"service": service, "dummy_value": value}) + "\n")
        state.chmod(0o600)

        def owned_probe(action):
            owner.assert_owned()
            probe(owner.target, action, service, value, runner=runner)
            owner.assert_owned()

        owned_probe("absent")
        try:
            owned_probe("add")
            owner.replace(candidate)
            owned_probe("compare")
            owned_probe("delete")
            owned_probe("absent")
        finally:
            try:
                owner.assert_backup()
                cleanup_probe(owner.target, service, value, runner=cleanup_runner, ownership_check=owner.assert_owned)
            except BaseException as failure:
                owner.keep_state = True
                raise RuntimeError("probe cleanup unverified; recovery state retained at " + str(owner.directory)) from failure
        owner.restore()
        owned_probe("absent")
        return {"cross_build_keychain": "passed", "different_binary_bytes": True,
                "same_designated_requirement": True, "approval_ui": False,
                "existing_item_read_by_build_b": True, "cleanup_verified": True,
                "production_binary_restored": True, "scope": "random own-created dummy only"}

"""Opt-in cross-build probe, restricted to a random own-created dummy item."""
import argparse
import json
import os
import pathlib
import subprocess
import sys
from installation_lifecycle import cross_build_check, validate_identity


def main(argv=None, *, runner=subprocess.run):
    parser = argparse.ArgumentParser(description="Check same-item cross-build Keychain access under the installation lock")
    parser.add_argument("--installed", type=pathlib.Path, default=pathlib.Path.home() / ".local/bin/ghealth")
    args = parser.parse_args(argv)
    if sys.platform != "darwin":
        raise RuntimeError("macOS and a certificate SIGN_IDENTITY are required; no skipped pass")
    identity = validate_identity(os.environ.get("SIGN_IDENTITY", ""))
    root = pathlib.Path(__file__).resolve().parent.parent
    result = cross_build_check(args.installed, root, identity, go=os.environ.get("GO", "go"), runner=runner)
    print(json.dumps(result))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        print("ghoops cross-build check: " + str(error), file=sys.stderr)
        raise SystemExit(1)

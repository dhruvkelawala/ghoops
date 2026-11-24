"""Production install entry point. Tests inject the subprocess boundary."""
import argparse
import os
import pathlib
import subprocess
import sys
from installation_lifecycle import production_install, validate_identity


def main(argv=None, *, runner=subprocess.run):
    parser = argparse.ArgumentParser(description="Install a certificate-signed ghoops without credential identity migration")
    parser.add_argument("--installed", type=pathlib.Path, default=pathlib.Path.home() / ".local/bin/ghealth")
    parser.add_argument("--ldflags", default="")
    args = parser.parse_args(argv)
    if sys.platform != "darwin":
        raise RuntimeError("production credential storage requires macOS; no skipped pass")
    identity = validate_identity(os.environ.get("SIGN_IDENTITY", ""))
    root = pathlib.Path(__file__).resolve().parent.parent
    output = production_install(args.installed, root, identity, go=os.environ.get("GO", "go"),
                                ldflags=args.ldflags, runner=runner)
    print(output.strip())


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        print("ghoops install: " + str(error), file=sys.stderr)
        raise SystemExit(1)

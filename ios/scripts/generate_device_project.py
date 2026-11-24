import os
from pathlib import Path
import re


IDENTITY_KEYS = {
    "TEAM_ID": r"[A-Z0-9]{10}",
    "BUNDLE_ID_PREFIX": r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*",
    "APP_GROUP": r"group\.[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*",
}


def main():
    path = os.environ.get("GHOOPS_IOS_IDENTITY") or "~/.config/ghealth/ios-identity"
    try:
        lines = Path(path).expanduser().read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        keys = ", ".join(IDENTITY_KEYS)
        raise SystemExit(f"Missing iOS identity file {path}. Set {keys} in that file.")
    except (OSError, UnicodeError):
        raise SystemExit(f"Cannot read iOS identity file {path} as UTF-8.")

    identity = {}
    for number, line in enumerate(lines, start=1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        key = key.strip()
        if not separator or key not in IDENTITY_KEYS or key in identity:
            keys = ", ".join(IDENTITY_KEYS)
            raise SystemExit(f"Invalid line {number} in {path}. Set {keys} once each as KEY=value.")
        identity[key] = value.strip()

    environment = os.environ.copy()
    for key, pattern in IDENTITY_KEYS.items():
        value = identity.get(key)
        if not value:
            raise SystemExit(f"Missing {key} in iOS identity file {path}.")
        if not re.fullmatch(pattern, value):
            raise SystemExit(f"Invalid {key} in iOS identity file {path}.")
        environment[f"GHOOPS_IOS_{key}"] = value

    os.execvpe("xcodegen", ["xcodegen", "generate", "--spec", "ios/project.yml"], environment)


if __name__ == "__main__":
    main()

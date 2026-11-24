import collections
import json
import pathlib
import re
import sys


RULES = {
    "hex": re.compile(r"goopHex:"),
    "textstyle": re.compile(r"GoopTextStyle\("),
    "rawfont": re.compile(r"GoopFont\.(?:sofia|nunito)\("),
    "radius": re.compile(r"cornerRadius: [0-9]|CornerRadius\([0-9]"),
    "stale": re.compile(r"\?\s*0\.55\s*:"),
    "symbol": re.compile(r"Image\(systemName:"),
    "dialog": re.compile(r"\.confirmationDialog\("),
    "hrword": re.compile(r'"(?:NO HR|RECONNECTING)"'),
    "rawerror": re.compile(r"\blocalizedDescription\b"),
    "sofiaword": None,
    "enginenumber": None,
}
ALLOW = re.compile(r"// goop-lint: allow (\w+): (\S.*)\s*$")
TOKEN = re.compile(r"^\s*static let \w+ = SwiftUI\.Color\(goopHex: 0x[0-9A-F]{6}\)(\.opacity\([0-9.]+\))?$")
INTERPOLATION = r"\\\((?:[^()]|\([^()]*\))*\)"
STRING = re.compile(r'"(?:' + INTERPOLATION + r'|\\.|[^"\\])*"')
ESCAPE = re.compile(INTERPOLATION + r"|\\.")
VALUE_COMPONENT = re.compile(r"\b(?:GoopSheetRow|GoopBreakdownRow|GoopBreakdownTotal|GoopLevelScale|GoopWindowBar|GoopStatCells\.Cell)\(")
VALUE_END = re.compile(r",\s*[A-Za-z_]\w*\s*:|\)\s*(?:$|[.}])")


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    styles = sofia_styles(root)
    counts = collections.Counter()
    errors = []
    for folder in ("ios/GHealth", "ios/Shared", "ios/GHealthWidgets", "ios/GHealthCore/Sources/GHealthCore"):
        for path in sorted((root / folder).rglob("*.swift")):
            name = path.relative_to(root).as_posix()
            if name.startswith("ios/GHealth/Debug/Reference/"):
                continue
            for number, line in enumerate(path.read_text().splitlines(), 1):
                marker = ALLOW.search(line)
                used = False
                for rule, pattern in RULES.items():
                    if name.startswith("ios/GHealthCore/") and rule not in ("enginenumber", "rawerror"):
                        continue
                    if rule in ("enginenumber", "rawerror") and name.startswith(("ios/GHealth/Debug/", "ios/GHealthCore/Sources/GHealthCore/Fixtures/")):
                        continue
                    if rule == "hex" and name == "ios/Shared/Goop/GoopTokens.swift" and (TOKEN.fullmatch(line) or "init(goopHex:" in line):
                        continue
                    if rule == "textstyle" and path.name in ("GoopFont.swift", "GoopTokens.swift"):
                        continue
                    if rule == "rawfont" and path.name == "GoopFont.swift":
                        continue
                    if rule == "symbol" and (not name.startswith("ios/GHealth/") or name == "ios/GHealth/Components/Goop/GoopControls.swift"):
                        continue
                    if rule == "enginenumber":
                        matches = engine_numbers(line)
                    elif rule == "sofiaword":
                        matches = sofia_words(line, styles)
                    else:
                        matches = len(pattern.findall(line))
                    if matches and marker and marker[1] == rule:
                        used = True
                        continue
                    counts[f"{rule} {name}"] += matches
                    for _ in range(matches):
                        print(f"{name}:{number}: {rule}: {line.strip()[:120]}")
                if marker and not used:
                    errors.append(f"{name}:{number}: unused allow marker: {marker[1]}")
    try:
        baseline = json.loads((root / "scripts/goop_lint_baseline.json").read_text())
        if not isinstance(baseline, dict):
            raise ValueError("expected an object")
    except (OSError, ValueError) as error:
        print(f"invalid baseline: {error}")
        return 1
    for key in sorted(counts.keys() | baseline.keys()):
        count = counts[key]
        allowed = baseline.get(key, 0)
        if key in baseline and (key.partition(" ")[0] not in RULES or type(allowed) is not int or allowed <= 0):
            errors.append(f"invalid baseline: {key}")
        elif count > allowed:
            errors.append(f'new drift: "{key}" has {count}, baseline {allowed}')
        elif count < allowed:
            change = f'set "{key}" to {count}' if count else f'remove "{key}"'
            errors.append(f"stale baseline: {change}")
    if errors:
        print("\n".join(errors))
        return 1
    print(f"goop-lint ok: {sum(counts.values())} findings, all in baseline")
    return 0


def engine_numbers(line):
    if line.lstrip().startswith("//"):
        return 0
    count = 0
    for literal in STRING.finditer(line):
        text = without_escapes(literal[0])
        if (re.search(r"\s", text) and re.search(r"(?<![\w.%$])\d+(?:\.\d+)?(?!\w)", text)) or re.search(r"\d\s*–\s*\d", text):
            count += 1
    return count


def without_escapes(text):
    result = []
    index = 0
    while index < len(text):
        if text.startswith("\\(", index):
            index += 2
            depth = 1
            while index < len(text) and depth:
                if text[index] == "(":
                    depth += 1
                elif text[index] == ")":
                    depth -= 1
                index += 1
        elif text[index] == "\\":
            index += 2
        else:
            result.append(text[index])
            index += 1
    return "".join(result)


def sofia_styles(root):
    path = root / "ios/Shared/Goop/GoopTokens.swift"
    if not path.exists():
        return set()
    return {match[1] for line in path.read_text().splitlines()
            if "sofia: true" in line
            for match in re.finditer(r"case \.(\w+): GoopTextStyle\(", line)}


def sofia_words(line, styles):
    spans = []
    start = 0
    for call in re.finditer(r"\.goop\(([^)]*)\)", line):
        if styles.intersection(re.findall(r"\.(\w+)", call[1])):
            spans.append((start, call.start()))
        start = call.end()
    if not re.search(r"\bnunito:\s*true\b", line):
        for call in re.finditer(r"\bGoopPlot\.text\(", line):
            end = line.find("context:", call.end())
            if end >= 0:
                spans.append((call.end(), end))
    for call in VALUE_COMPONENT.finditer(line):
        value = re.search(r"\bvalue:\s*", line[call.end():])
        if value:
            start = call.end() + value.end()
            end = VALUE_END.search(line, start)
            spans.append((start, end.start() if end else len(line)))
    count = 0
    for literal in STRING.finditer(line):
        text = ESCAPE.sub(lambda match: "" if match[0].startswith("\\(") else match[0], literal[0])
        if re.search(r"[A-Za-z]", text) and any(start <= literal.start() and literal.end() <= end for start, end in spans):
            count += 1
    return count


if __name__ == "__main__":
    sys.exit(main())

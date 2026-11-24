import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest


class GoopLintTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.write("scripts/goop_lint_baseline.json", "{}")
        self.write("ios/Shared/Goop/GoopTokens.swift", "\n".join([
            "case .valueMid: GoopTextStyle(size: 17, sofia: true)",
            "case .axis: GoopTextStyle(size: 11, sofia: true)",
            "case .unitSmall: GoopTextStyle(size: 10, sofia: false)",
            "case .labelLane: GoopTextStyle(size: 10.5, sofia: false)",
        ]))
        shutil.copyfile(pathlib.Path(__file__).with_name("goop_lint.py"), self.root / "scripts/goop_lint.py")

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def baseline(self, counts):
        self.write("scripts/goop_lint_baseline.json", json.dumps(counts))

    def run_lint(self):
        result = subprocess.run([sys.executable, "-I", str(self.root / "scripts/goop_lint.py")], capture_output=True, text=True)
        self.assertEqual(result.stderr, "")
        return result.returncode, result.stdout

    def test_clean_tree_passes(self):
        self.assertEqual(self.run_lint(), (0, "goop-lint ok: 0 findings, all in baseline\n"))

    def test_each_rule_fires_once(self):
        samples = {
            "hex": "Color(goopHex: 0xABCDEF)",
            "textstyle": "GoopTextStyle(size: 12)",
            "rawfont": "GoopFont.sofia(12)",
            "radius": "RoundedRectangle(cornerRadius: 12)",
            "stale": "stale ? 0.55 : 1",
            "symbol": 'Image(systemName: "clock")',
            "dialog": '.confirmationDialog("Delete")',
            "hrword": 'Text("NO HR")',
            "sofiaword": 'Text("words").goop(.valueMid)',
            "enginenumber": 'Text("7 nights to start")',
            "rawerror": 'Text(error.localizedDescription)',
        }
        for rule, sample in samples.items():
            with self.subTest(rule=rule):
                self.write("ios/GHealth/Sample.swift", sample)
                code, output = self.run_lint()
                self.assertEqual(code, 1)
                self.assertIn(f"ios/GHealth/Sample.swift:1: {rule}:", output)
                self.assertIn(f'new drift: "{rule} ios/GHealth/Sample.swift" has 1, baseline 0', output)
                self.assertEqual(output.count("new drift:"), 1)

    def test_sofia_words_and_numeric_values(self):
        samples = [
            ('Text(range + " BPM").goop(.valueMid)', 1),
            ('HStack { Text("−10 MIN"); Text("NOW") }.goop(.axis)', 2),
            ('GoopPlot.text(GoopFormat.dateLabel(d, format: "MMM d"), context: c, x: 0, y: 0, size: 11, color: k)', 1),
            (r'GoopSheetRow(label: "Fell asleep in", value: m.map { "\($0) min" } ?? "—")', 1),
            ('Text(value).goop(.valueMid); Text("BPM").goop(.unitSmall)', 0),
            (r'Text("\(low)–\(high)").goop(.valueMid).accessibilityIdentifier("scale-hours")', 0),
            ('GoopPlot.text("HR", context: c, x: 0, y: 0, size: 10.5, color: k, nunito: true)', 0),
            ('GoopSheetRow(label: "Fell asleep in", value: "4", unit: "min")', 0),
            ('GoopBreakdownRow(label: "HRV", value: line.value, identifier: "recovery-hrv")', 0),
            (r'Text("\(Int(value))%").goop(.valueMid)', 0),
            ('GoopSheetRow(label: "4", value: "4 min").goop(.valueMid)', 1),
        ]
        for sample, count in samples:
            with self.subTest(sample=sample):
                self.write("ios/GHealth/Sample.swift", sample)
                code, output = self.run_lint()
                self.assertEqual(code, int(count > 0))
                self.assertEqual(output.count(": sofiaword:"), count)

    def test_sofia_allow_marker_and_missing_tokens(self):
        self.write("ios/GHealth/Sample.swift", 'Text("words").goop(.valueMid) // goop-lint: allow sofiaword: quoted reading')
        self.assertEqual(self.run_lint()[0], 0)
        self.write("ios/GHealth/Sample.swift", 'Text("words").goop(.valueMid)')
        (self.root / "ios/Shared/Goop/GoopTokens.swift").unlink()
        self.assertEqual(self.run_lint()[0], 0)

    def test_engine_numbers_and_paths(self):
        app = "ios/GHealth/Sample.swift"
        first = 'GoopFootnote(text: "7 nights to start · 14 for full confidence")'
        samples = [
            (app, first, 1),
            (app, 'Text("Strain under 10.0 is considered light.")', 1),
            (app, 'Band(name: "LOW", range: "0–33", tone: .recoveryLow)', 1),
            (app, r'Text("\(GoopFormat.number(v, decimals: 1)) of 21")', 1),
            (app, r'Text("\(needed) nights to start · \(full) for full confidence")', 0),
            (app, r'Text("Last: \($0.formatted(.dateTime.weekday(.abbreviated)))")', 0),
            (app, r'Text("ZONE \(zone)")', 0),
            (app, r'Text("Zones \(a)–\(b)")', 0),
            (app, 'Image(systemName: "gauge.with.dots.needle.33percent")', 0),
            (app, 'let day = "2026-03-10"', 0),
            (app, 'String(format: "%d:%02d", h, m)', 0),
            (app, '// Strain under 10.0 is light', 0),
            (app, r'Text("7\nnights")', 0),
            ("ios/GHealthCore/Sources/GHealthCore/Sample.swift", first, 1),
            ("ios/GHealthCore/Sources/GHealthCore/Fixtures/Sample.swift", first, 0),
            ("ios/GHealth/Debug/Sample.swift", first, 0),
            ("ios/GHealthCore/Sources/GHealthCore/Sample.swift", 'Image(systemName: "x")', 0),
        ]
        for name, sample, count in samples:
            with self.subTest(name=name, sample=sample):
                self.write(name, sample)
                code, output = self.run_lint()
                self.assertEqual(code, int(count > 0 or (name == app and sample.startswith("Image("))))
                self.assertEqual(output.count(": enginenumber:"), count)
                (self.root / name).unlink()

    def test_raw_errors_are_blocked_except_in_debug_files(self):
        for folder, blocked in [
            ("ios/GHealth", True), ("ios/Shared", True), ("ios/GHealthWidgets", True),
            ("ios/GHealthCore/Sources/GHealthCore", True),
            ("ios/GHealth/Debug", False), ("ios/GHealthCore/Sources/GHealthCore/Fixtures", False),
        ]:
            with self.subTest(folder=folder):
                name = f"{folder}/Sample.swift"
                self.write(name, 'let message = error.localizedDescription')
                code, output = self.run_lint()
                self.assertEqual(code, int(blocked))
                self.assertEqual(output.count(": rawerror:"), int(blocked))
                (self.root / name).unlink()

    def test_token_definition_passes_and_gradient_fails(self):
        name = "ios/Shared/Goop/GoopTokens.swift"
        self.write(name, "    static let strain = SwiftUI.Color(goopHex: 0x0294E7)\n    static let dim = SwiftUI.Color(goopHex: 0x0294E7).opacity(0.5)\n    init(goopHex: Int) {}")
        self.assertEqual(self.run_lint()[0], 0)
        self.write(name, "    static let gradient = LinearGradient(colors: [SwiftUI.Color(goopHex: 0x0294E7)])")
        code, output = self.run_lint()
        self.assertEqual(code, 1)
        self.assertIn(f"{name}:1: hex:", output)

    def test_allow_marker_exempts_only_its_rule(self):
        self.write("ios/GHealth/Sample.swift", "GoopFont.sofia(12); Color(goopHex: 0xABCDEF) // goop-lint: allow rawfont: fixed numerals")
        self.baseline({"hex ios/GHealth/Sample.swift": 1})
        code, output = self.run_lint()
        self.assertEqual(code, 0)
        self.assertIn(": hex:", output)
        self.assertNotIn(": rawfont:", output)
        self.assertIn("goop-lint ok: 1 findings, all in baseline", output)

    def test_unused_marker_fails(self):
        self.write("ios/GHealth/Sample.swift", "Text(title) // goop-lint: allow rawfont: fixed numerals")
        code, output = self.run_lint()
        self.assertEqual(code, 1)
        self.assertIn("unused allow marker: rawfont", output)

    def test_over_baseline_fails(self):
        self.write("ios/GHealth/Sample.swift", "Color(goopHex: 0xABCDEF); Color(goopHex: 0xABCDEF)")
        self.baseline({"hex ios/GHealth/Sample.swift": 1})
        code, output = self.run_lint()
        self.assertEqual(code, 1)
        self.assertIn('new drift: "hex ios/GHealth/Sample.swift" has 2, baseline 1', output)

    def test_under_baseline_fails_with_new_count(self):
        key = "hex ios/GHealth/Sample.swift"
        self.write("ios/GHealth/Sample.swift", "Color(goopHex: 0xABCDEF)")
        self.baseline({key: 2})
        code, output = self.run_lint()
        self.assertEqual(code, 1)
        self.assertIn(f'stale baseline: set "{key}" to 1', output)
        self.write("ios/GHealth/Sample.swift", "Text(title)")
        code, output = self.run_lint()
        self.assertEqual(code, 1)
        self.assertIn(f'stale baseline: remove "{key}"', output)

    def test_debug_reference_is_ignored(self):
        self.write("ios/GHealth/Debug/Reference/Sample.swift", "Color(goopHex: 0xABCDEF)")
        self.assertEqual(self.run_lint()[0], 0)

    def test_symbols_outside_app_are_allowed(self):
        for folder in ("ios/Shared", "ios/GHealthWidgets"):
            self.write(f"{folder}/Sample.swift", 'Image(systemName: "clock")')
        self.assertEqual(self.run_lint()[0], 0)


if __name__ == "__main__":
    unittest.main()

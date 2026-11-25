"""Black-box checks. No credentials, browser, network, or health records are read."""
import json
import pathlib
import subprocess
import sys
import tempfile

binary = str(pathlib.Path(sys.argv[1]).resolve())
checks = 0
with tempfile.TemporaryDirectory(prefix="ghealth-smoke-") as state:
    state = str(pathlib.Path(state).resolve())
    def run(*args, code=0):
        global checks
        result = subprocess.run(
            [binary, "--state-dir", state, *args],
            capture_output=True, text=True, timeout=15,
        )
        assert result.returncode == code, (args, result.returncode, result.stderr)
        checks += 1
        return result

    help_text = run("help").stdout
    assert help_text.startswith("ghoops:") and "Usage: ghoops " in help_text
    assert "Google Health v4" in help_text
    with tempfile.TemporaryDirectory(prefix="ghoops-alias-") as aliases:
        old_binary = pathlib.Path(aliases) / "ghealth"
        old_binary.symlink_to(binary)
        result = subprocess.run([str(old_binary), "--state-dir", state, "help"],
                                capture_output=True, text=True, timeout=15)
        assert result.returncode == 0 and result.stdout == help_text
        checks += 1
    assert "read-only" in run("sync", "--help").stdout
    version = json.loads(run("version", "--json").stdout)
    assert version["version"] and version["revision"]
    doctor = json.loads(run("doctor", "--offline", "--json").stdout)
    assert not doctor["credentials_checked"] and not doctor["health_records_checked"]
    assert doctor["source"] == "google_health_v4"
    today = json.loads(run("today", "--json").stdout)
    assert len(today["days"]) == 1 and today["timezone"] == "Europe/London"
    day = today["days"][0]
    for metric in (day["hrv_rmssd_ms"], day["steps"], day["sleep"]["asleep_minutes"]):
        assert metric["status"] == "not_synced" and metric["value"] is None
    assert day["exercise"]["workouts"] == []
    assert len(json.loads(run("summary", "--days", "7", "--json").stdout)["days"]) == 7
    assert len(json.loads(run("trends", "--days", "14", "--json").stdout)["days"]) == 14
    export = json.loads(run("data", "export").stdout)
    assert export["records"] == [] and export["coverage"] == []
    run("sync", "--days", "0", code=2)
    run("today", "--date", "2026-02-30", code=2)
    run("unknown", code=2)
    run("auth", "login", code=2)
    run("doctor", "--offline", "--live", code=2)
    pair = run("pair", "--json", code=2)
    assert pair.stdout == "" and "ghv" not in pair.stderr
    assert json.loads(pair.stderr)["error"]["code"] == "invalid_request"
    assert not list(pathlib.Path(state).iterdir()), "offline commands wrote state"
    for command in ("day", "sleep", "days", "workouts", "status", "snapshot", "brief"):
        body = json.loads(run(command, "--json").stdout)
        assert body["schema_version"] == 2 and body["kind"] == command
        if command != "brief":
            assert body["freshness"]["last_collect_status"] == "never"
        if command == "day":
            assert body["vitals"]["metrics"]["hrv_rmssd"]["status"] == "not_synced"
            assert body["activity"]["steps"]["status"] == "not_synced"
print(f"Black-box smoke passed: {checks} assertions through CLI invocations; no live data.")

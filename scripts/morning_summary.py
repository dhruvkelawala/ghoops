import argparse
import json
import sys


def main():
    parser = argparse.ArgumentParser(description="Reduce local ghoops JSON to a minimal morning summary")
    parser.add_argument("--include-values", action="store_true", help="include four fresh numerical metrics only after user disclosure consent")
    args = parser.parse_args()
    try:
        document = json.load(sys.stdin)
        if not isinstance(document, dict) or document.get("schema_version") != 1 or document.get("source") != "google_health_v4" or document.get("synthetic_fixture"):
            raise ValueError("unsupported summary")
        days = []
        for day in document["days"][-2:]:
            selected = {"date": day["date"]}
            metrics = {"sleep_minutes": day["sleep"]["asleep_minutes"], "hrv_rmssd_ms": day["hrv_rmssd_ms"], "resting_heart_rate_bpm": day["resting_heart_rate_bpm"], "steps": day["steps"], "exercise": day["exercise"]["coverage"]}
            for name, metric in metrics.items():
                selected[name] = {"status": metric["status"], "stale": metric["stale"]}
                if args.include_values and name != "exercise" and metric["status"] == "available" and not metric["stale"] and metric.get("value") is not None:
                    selected[name].update(value=metric["value"], unit=metric["unit"])
            days.append(selected)
        print(json.dumps({"source": document["source"], "timezone": document["timezone"], "disclosure": "minimal_values" if args.include_values else "availability_only", "days": days}))
        return 0
    except (KeyError, TypeError, ValueError):
        print("morning summary requires valid ghoops summary JSON", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

package cli

import (
	"context"
	"fmt"

	"github.com/dhruvkelawala/ghoops/internal/health"
)

// apiProbe reports which Google Health routes return records for this account.
// It prints counts and error codes only, never record values, and stores nothing.
func (a *app) apiProbe(ctx context.Context, args []string) error {
	f := flags("probe")
	days := f.Int("days", 14, "")
	v2 := f.Bool("v2", false, "verify v2 API shapes; counts only")
	diagnose := f.Bool("diagnose-fields", false, "with --v2: per-field missing/range counts for streams that failed validation")
	if err := parse(f, args); err != nil {
		return err
	}
	if *days < 1 || *days > 90 {
		return usageError{"--days must be between 1 and 90"}
	}
	today, _ := a.date(a.now.In(a.loc).Format("2006-01-02"))
	end := today.AddDate(0, 0, 1)
	if *v2 && *diagnose {
		return a.emit(map[string]any{"schema_version": 2, "kind": "probe_fields", "days": *days, "streams": health.New(a.auth.Access).DiagnoseFields(ctx, end.AddDate(0, 0, -*days), end)})
	}
	if *v2 {
		return a.emit(struct {
			Version int                    `json:"schema_version"`
			Kind    string                 `json:"kind"`
			Results []health.ProbeV2Result `json:"results"`
		}{2, "probe", health.New(a.auth.Access).ProbeV2(ctx, today.AddDate(0, 0, -2), end)})
	}
	start := end.AddDate(0, 0, -*days)
	results := health.New(a.auth.Access).Probe(ctx, start, end)
	if a.json {
		return a.emit(map[string]any{"schema_version": 1, "source": health.Source, "days": *days, "results": results})
	}
	for _, r := range results {
		more := ""
		if r.More {
			more = "+"
		}
		fmt.Fprintf(a.out, "%-40s %-12s %-8s %6d%s %s\n", r.Target, r.Method, r.Status, r.Records, more, r.Error)
	}
	return nil
}

package collect

import (
	"sort"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/cache"
	"github.com/dhruvkelawala/ghoops/internal/health"
	"github.com/dhruvkelawala/ghoops/internal/store2"
)

func merge(state *store2.State2, o output, status, code string, now time.Time) {
	j := o.job
	if j.resource != "" {
		if state.User == nil {
			state.User = map[string]store2.UserResource{}
		}
		resource := state.User[j.resource]
		resource.Status = status
		if status == "unsupported" {
			resource.Status = "unavailable"
		}
		if o.err == nil {
			resource.Body, resource.FetchedAt, resource.Error = o.body, &now, nil
		} else {
			resource.Error = &code
			if status == "permission_missing" {
				resource.Body, resource.FetchedAt = nil, nil
			}
		}
		state.User[j.resource] = resource
		return
	}
	counts := map[string]int{}
	if o.err == nil {
		switch j.route {
		case "rollUp":
			kept := []store2.MinuteDay{}
			for _, old := range state.HRMinutes {
				if old.Date != j.from.Format("2006-01-02") {
					kept = append(kept, old)
				}
			}
			day := store2.MinuteDay{Date: j.from.Format("2006-01-02"), Windows: []store2.Minute{}}
			for _, m := range o.minutes {
				day.Windows = append(day.Windows, store2.Minute{Start: m.Start, Min: m.Min, Avg: m.Avg, Max: m.Max})
			}
			state.HRMinutes = append(kept, day)
			counts[day.Date] = len(day.Windows)
		case "dailyRollUp":
			kept := []store2.DailyRollup{}
			for _, old := range state.DailyRollups {
				if old.Type != j.kind.ID || old.Date < j.from.Format("2006-01-02") || old.Date >= j.until.Format("2006-01-02") {
					kept = append(kept, old)
				}
			}
			for _, day := range o.days {
				kept = append(kept, store2.DailyRollup{Type: j.kind.ID, Date: day.Date, Value: day.Value})
				counts[day.Date]++
			}
			state.DailyRollups = kept
		default:
			replaceRecords(state, j, o.records)
			for _, record := range o.records {
				counts[record.Date]++
			}
		}
	}
	for date := j.from; date.Before(j.until); date = date.AddDate(0, 0, 1) {
		row := cache.Coverage{Type: j.kind.ID, Stream: j.route, Date: date.Format("2006-01-02"), Status: status, AttemptAt: now, Error: code}
		kept := []cache.Coverage{}
		for _, old := range state.Coverage {
			if old.Type == row.Type && old.Stream == row.Stream && old.Date == row.Date {
				row.SuccessAt, row.Count = old.SuccessAt, old.Count
			} else {
				kept = append(kept, old)
			}
		}
		if o.err == nil {
			row.SuccessAt, row.Count = &now, counts[row.Date]
		}
		state.Coverage = append(kept, row)
	}
}

func replaceRecords(state *store2.State2, j job, records []health.Record) {
	stream := "raw"
	if j.route == "reconcile" {
		stream = "reconciled"
	}
	names := map[string]bool{}
	for _, record := range records {
		if name := record.Identity(); name != "" {
			names[name] = true
		}
	}
	affected := map[string]bool{}
	kept := []health.Record{}
	for _, old := range state.Records {
		if old.Type == j.kind.ID && old.Stream == stream {
			if old.Date >= j.from.Format("2006-01-02") && old.Date < j.until.Format("2006-01-02") {
				continue
			}
			if names[old.Identity()] {
				affected[old.Date] = true
				continue
			}
		}
		kept = append(kept, old)
	}
	state.Records = append(kept, records...)
	for i := range state.Coverage {
		c := &state.Coverage[i]
		if c.Type == j.kind.ID && c.Stream == j.route && affected[c.Date] {
			c.Status, c.Error, c.Count = "stale", "record_timestamp_changed", 0
			for _, record := range state.Records {
				if record.Type == j.kind.ID && record.Stream == stream && record.Date == c.Date {
					c.Count++
				}
			}
		}
	}
}

func sortState(state *store2.State2) {
	sort.Slice(state.Records, func(i, j int) bool {
		a, b := state.Records[i], state.Records[j]
		if a.Date != b.Date {
			return a.Date < b.Date
		}
		if a.Type != b.Type {
			return a.Type < b.Type
		}
		if a.Stream != b.Stream {
			return a.Stream < b.Stream
		}
		return string(a.Raw) < string(b.Raw)
	})
	sort.Slice(state.Coverage, func(i, j int) bool {
		a, b := state.Coverage[i], state.Coverage[j]
		if a.Date != b.Date {
			return a.Date < b.Date
		}
		if a.Type != b.Type {
			return a.Type < b.Type
		}
		return a.Stream < b.Stream
	})
	sort.Slice(state.HRMinutes, func(i, j int) bool { return state.HRMinutes[i].Date < state.HRMinutes[j].Date })
	sort.Slice(state.DailyRollups, func(i, j int) bool {
		a, b := state.DailyRollups[i], state.DailyRollups[j]
		if a.Date != b.Date {
			return a.Date < b.Date
		}
		return a.Type < b.Type
	})
}

package cache_test

import (
	"context"
	"encoding/json"
	"errors"
	"reflect"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/cache"
	"github.com/dhruvkelawala/ghoops/internal/health"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

type movedRecordFetcher struct {
	kind, stream string
	records      []health.Record
	err          error
}

func (f movedRecordFetcher) Fetch(_ context.Context, kind health.Kind, stream string, _, _ time.Time) ([]health.Record, error) {
	if kind.ID == f.kind && stream == f.stream {
		return f.records, f.err
	}
	return nil, nil
}

func namedIntervalRecord(t *testing.T, kind, stream, date, name string) health.Record {
	t.Helper()
	field := "name"
	if stream == "reconciled" {
		field = "dataPointName"
	}
	point := map[string]any{}
	if name != "" {
		point[field] = name
	}
	interval := map[string]string{"startTime": date + "T06:00:00Z", "endTime": date + "T07:00:00Z"}
	if kind == "sleep" {
		point[kind] = map[string]any{"interval": interval, "summary": map[string]string{"minutesAsleep": "60"}}
	} else {
		point[kind] = map[string]any{"interval": interval, "exerciseType": "WEIGHTS"}
	}
	raw, err := json.Marshal(point)
	if err != nil {
		t.Fatal(err)
	}
	return testutil.Record(t, kind, stream, date, string(raw))
}

func TestSyncFailedPartialTimestampMoveRetainsPriorRecordsAndCoverage(t *testing.T) {
	for _, tc := range []struct{ kind, stream string }{{"sleep", "raw"}, {"sleep", "reconciled"}, {"exercise", "raw"}} {
		t.Run(tc.kind+"/"+tc.stream, func(t *testing.T) {
			store := cache.Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
			from := time.Date(2026, 10, 12, 0, 0, 0, 0, time.UTC)
			oldDate, newDate := "2026-10-10", "2026-10-12"
			old := cache.Empty()
			old.Account, old.Timezone = "synthetic-user", "UTC"
			old.Records = []health.Record{
				namedIntervalRecord(t, tc.kind, tc.stream, oldDate, "synthetic-moved"),
				namedIntervalRecord(t, tc.kind, tc.stream, newDate, "synthetic-existing"),
			}
			lastSync := time.Date(2026, 10, 11, 12, 0, 0, 0, time.UTC)
			oldCoverage := cache.Coverage{Type: tc.kind, Stream: tc.stream, Date: oldDate, Status: "ok", AttemptAt: lastSync, SuccessAt: &lastSync, Count: 1}
			old.Coverage = []cache.Coverage{oldCoverage, {Type: tc.kind, Stream: tc.stream, Date: newDate, Status: "ok", AttemptAt: lastSync, SuccessAt: &lastSync, Count: 1}}
			if err := store.Save(old); err != nil {
				t.Fatal(err)
			}
			fetcher := movedRecordFetcher{kind: tc.kind, stream: tc.stream, records: []health.Record{namedIntervalRecord(t, tc.kind, tc.stream, newDate, "synthetic-moved")}, err: errors.New("synthetic later-page failure")}
			result, err := cache.Sync(context.Background(), store, fetcher, resolveSyntheticAccount("synthetic-user"), from, from.AddDate(0, 0, 1))
			if err == nil || result.Complete || result.Records != 0 {
				t.Fatal("partial timestamp move was accepted", result, err)
			}
			loaded, err := store.Load()
			if err != nil || !reflect.DeepEqual(loaded.Records, old.Records) {
				t.Fatal("failed stream changed prior records inside or outside the requested range", loaded.Records, err)
			}
			for _, c := range loaded.Coverage {
				if c.Type != tc.kind || c.Stream != tc.stream {
					continue
				}
				switch c.Date {
				case oldDate:
					if !reflect.DeepEqual(c, oldCoverage) {
						t.Fatal("partial page incorrectly invalidated old-date coverage", c)
					}
				case newDate:
					if c.Status != "unavailable" || c.Error != "request_failed" || c.Count != 1 || c.SuccessAt == nil || !c.SuccessAt.Equal(lastSync) {
						t.Fatal("failed collection did not retain prior count/success metadata", c)
					}
				}
			}
		})
	}
}

func TestSyncNamedTimestampMoveInvalidatesOldDateWithoutCollapsingOtherRecords(t *testing.T) {
	for _, tc := range []struct{ kind, stream string }{{"sleep", "raw"}, {"sleep", "reconciled"}, {"exercise", "raw"}} {
		t.Run(tc.kind+"/"+tc.stream, func(t *testing.T) {
			loc, err := time.LoadLocation("Europe/London")
			if err != nil {
				t.Fatal(err)
			}
			from := time.Date(2026, 10, 12, 0, 0, 0, 0, loc)
			store := cache.Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
			oldDate, newDate, untouchedDate := "2026-10-10", "2026-10-12", "2026-10-09"
			otherKind := "exercise"
			if tc.kind == "exercise" {
				otherKind = "sleep"
			}
			otherStream := "reconciled"
			if tc.stream == "reconciled" {
				otherStream = "raw"
			}
			oldMoved := namedIntervalRecord(t, tc.kind, tc.stream, oldDate, "synthetic-moved")
			keep := namedIntervalRecord(t, tc.kind, tc.stream, oldDate, "synthetic-unrelated")
			nameless := namedIntervalRecord(t, tc.kind, tc.stream, oldDate, "")
			otherType := namedIntervalRecord(t, otherKind, "raw", oldDate, "synthetic-moved")
			untouched := namedIntervalRecord(t, tc.kind, tc.stream, untouchedDate, "synthetic-untouched")
			old := cache.Empty()
			old.Account, old.Timezone = "synthetic-user", loc.String()
			old.Records = []health.Record{oldMoved, keep, nameless, otherType, untouched}
			if tc.kind == "sleep" {
				old.Records = append(old.Records, namedIntervalRecord(t, tc.kind, otherStream, oldDate, "synthetic-moved"))
			}
			lastSync := time.Date(2026, 10, 11, 12, 0, 0, 0, time.UTC)
			oldCoverage := cache.Coverage{Type: tc.kind, Stream: tc.stream, Date: oldDate, Status: "ok", AttemptAt: lastSync, SuccessAt: &lastSync, Count: 3}
			untouchedCoverage := cache.Coverage{Type: tc.kind, Stream: tc.stream, Date: untouchedDate, Status: "ok", AttemptAt: lastSync, SuccessAt: &lastSync, Count: 1}
			otherCoverage := cache.Coverage{Type: otherKind, Stream: "raw", Date: oldDate, Status: "ok", AttemptAt: lastSync, SuccessAt: &lastSync, Count: 1}
			old.Coverage = []cache.Coverage{oldCoverage, untouchedCoverage, otherCoverage}
			if tc.kind == "sleep" {
				old.Coverage = append(old.Coverage, cache.Coverage{Type: tc.kind, Stream: otherStream, Date: oldDate, Status: "ok", AttemptAt: lastSync, SuccessAt: &lastSync, Count: 1})
			}
			if err := store.Save(old); err != nil {
				t.Fatal(err)
			}
			freshMoved := namedIntervalRecord(t, tc.kind, tc.stream, newDate, "synthetic-moved")
			freshNameless := namedIntervalRecord(t, tc.kind, tc.stream, newDate, "")
			result, err := cache.Sync(context.Background(), store, movedRecordFetcher{kind: tc.kind, stream: tc.stream, records: []health.Record{freshMoved, freshNameless}}, resolveSyntheticAccount("synthetic-user"), from, from.AddDate(0, 0, 1))
			if err != nil || result.Records != 2 {
				t.Fatal("timestamp-move collection failed", result, err)
			}
			loaded, err := store.Load()
			if err != nil {
				t.Fatal(err)
			}
			for _, row := range loaded.Records {
				if reflect.DeepEqual(row, oldMoved) {
					t.Fatal("old identified interval survived outside the recollected range after its timestamp moved")
				}
			}
			want := append([]health.Record{}, old.Records[1:]...)
			want = append(want, freshMoved, freshNameless)
			if len(loaded.Records) != len(want) {
				t.Fatalf("unrelated identity or nameless record was collapsed: got %d records, want %d", len(loaded.Records), len(want))
			}
			for _, expected := range want {
				found := false
				for _, row := range loaded.Records {
					found = found || reflect.DeepEqual(row, expected)
				}
				if !found {
					t.Fatalf("unaffected or fresh record was lost: %s/%s %s %s", expected.Type, expected.Stream, expected.Date, expected.Raw)
				}
			}
			coverage := map[string]cache.Coverage{}
			for _, c := range loaded.Coverage {
				coverage[c.Type+"/"+c.Stream+"/"+c.Date] = c
			}
			invalidated := coverage[tc.kind+"/"+tc.stream+"/"+oldDate]
			if invalidated.Status != "stale" || invalidated.Error != "record_timestamp_changed" || invalidated.Count != 2 || invalidated.SuccessAt == nil || !invalidated.SuccessAt.Equal(lastSync) || !invalidated.AttemptAt.Equal(lastSync) {
				t.Fatal("old-date coverage still claims completeness or has incorrect retained count/history", invalidated)
			}
			for _, c := range old.Coverage[1:] {
				if !reflect.DeepEqual(coverage[c.Type+"/"+c.Stream+"/"+c.Date], c) {
					t.Fatal("unaffected date/type/stream coverage changed", c)
				}
			}
			freshCoverage := coverage[tc.kind+"/"+tc.stream+"/"+newDate]
			if freshCoverage.Status != "ok" || freshCoverage.Count != 2 || freshCoverage.SuccessAt == nil {
				t.Fatal("new-date coverage does not describe the refreshed records", freshCoverage)
			}
		})
	}
}

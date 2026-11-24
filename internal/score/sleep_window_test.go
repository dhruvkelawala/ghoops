package score_test

import (
	"encoding/json"
	"math/rand"
	"os"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/score"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestSleepRuleCases(t *testing.T) {
	raw, err := os.ReadFile("../../fixtures/v2/sleep_edit/rule_cases.json")
	if err != nil {
		t.Fatal(err)
	}
	var vectors struct {
		Cases []struct {
			Name     string                 `json:"name"`
			Input    score.SleepWindowInput `json:"input"`
			Expected json.RawMessage        `json:"expected"`
		} `json:"cases"`
	}
	if err := json.Unmarshal(raw, &vectors); err != nil {
		t.Fatal(err)
	}
	if len(vectors.Cases) == 0 {
		t.Fatal("no sleep rule cases")
	}
	for _, tc := range vectors.Cases {
		t.Run(tc.Name, func(t *testing.T) {
			testutil.CompareJSON(t, score.ComputeSleepWindow(tc.Input), tc.Expected, false)
		})
	}
}

func TestUnstagedFeedsPriorNightDebt(t *testing.T) {
	for _, tc := range []struct {
		fixture string
		debt    int
	}{{"full", 22}, {"sleep_unstaged", 14}} {
		e := engine(t, fixtureState(t, tc.fixture), "2026-03-11T14:30:00Z", config.Defaults())
		if got := e.Sleep("2026-03-11").Need.DebtExtra; got != tc.debt {
			t.Fatalf("%s prior-night debt: got %d want %d", tc.fixture, got, tc.debt)
		}
	}
}

// A segment Google's total already counts can go missing from the detail
// (oss-data-audit row 1). Its minutes must count once, so every score that
// reads the night stays as it was.
func TestMissingCountedSegmentKeepsScores(t *testing.T) {
	gap := fixtureState(t, "full")
	for i, r := range gap.Records {
		if r.Type != "sleep" || r.Date != "2026-03-10" {
			continue
		}
		var point map[string]any
		if err := json.Unmarshal(r.Raw, &point); err != nil {
			t.Fatal(err)
		}
		sleep := point["sleep"].(map[string]any)
		kept := []any{}
		for _, stage := range sleep["stages"].([]any) {
			if stage.(map[string]any)["startTime"] != "2026-03-09T23:16:00Z" {
				kept = append(kept, stage)
			}
		}
		if len(kept) != 21 {
			t.Fatalf("kept %d stages", len(kept))
		}
		sleep["stages"] = kept
		raw, _ := json.Marshal(point)
		gap.Records[i].Raw = raw
	}
	for _, tc := range []struct{ date, now string }{{"2026-03-10", "2026-03-10T14:30:00Z"}, {"2026-03-11", "2026-03-11T14:30:00Z"}} {
		want, got := engine(t, fixtureState(t, "full"), tc.now, config.Defaults()), engine(t, gap, tc.now, config.Defaults())
		for name, pair := range map[string][2]any{
			"sleep":    {want.Sleep(tc.date), got.Sleep(tc.date)},
			"recovery": {want.Recovery(tc.date), got.Recovery(tc.date)},
			"plan":     {want.SleepPlan(tc.date), got.SleepPlan(tc.date)},
		} {
			a, _ := json.Marshal(pair[0])
			b, _ := json.Marshal(pair[1])
			if string(a) != string(b) {
				t.Errorf("%s %s changed:\nwant %s\ngot  %s", tc.date, name, a, b)
			}
		}
	}
	if s := engine(t, gap, "2026-03-10T14:30:00Z", config.Defaults()).Sleep("2026-03-10"); *s.Asleep != 415 || *s.Efficiency != 95 {
		t.Fatalf("asleep %d efficiency %d", *s.Asleep, *s.Efficiency)
	}
}

// Whatever Google sends, a night is never more asleep than its window.
func TestSleepWindowStaysWithinTimeInBed(t *testing.T) {
	r := rand.New(rand.NewSource(32))
	base := time.Date(2026, 3, 10, 0, 0, 0, 0, time.UTC)
	at := func(m int) time.Time { return base.Add(time.Duration(m) * time.Minute) }
	stages := []string{"light", "deep", "rem", "asleep", "awake", "restless"}
	for n := 0; n < 5000; n++ {
		length := 30 + r.Intn(600)
		in := score.SleepWindowInput{Google: score.SleepGoogle{Start: at(0), End: at(length), StageMinutes: map[string]*int{}, StageSegments: map[string]*int{}}}
		staged := 0
		for m := 0; m < length; {
			next := min(length, m+1+r.Intn(60))
			stage := stages[r.Intn(len(stages))]
			if stage != "awake" && stage != "restless" {
				staged += next - m
			}
			if r.Intn(5) > 0 {
				in.Segments = append(in.Segments, score.Segment{Start: at(m), End: at(next), Stage: stage})
			}
			m = next
		}
		other := r.Intn(length+60) - 10
		switch r.Intn(4) {
		case 0:
			in.Google.Asleep = nil
		case 1:
			in.Google.Asleep = &staged
		default:
			in.Google.Asleep = &other
		}
		start := r.Intn(121) - 60
		in.Window = score.Span{Start: at(start), End: at(max(start+1, length+r.Intn(121)-60))}
		got := score.ComputeSleepWindow(in)
		if got.Asleep != nil && (*got.Asleep < 0 || *got.Asleep > got.InBed || got.Efficiency == nil || *got.Efficiency > 100) {
			t.Fatalf("case %d: asleep %d in bed %d efficiency %v", n, *got.Asleep, got.InBed, got.Efficiency)
		}
		if u := got.Stages["unstaged"].Minutes; u != nil && *u < 0 {
			t.Fatalf("case %d: unstaged %d", n, *u)
		}
	}
}

package score

import (
	"math"
	"sort"
	"strings"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/health"
)

type Span struct {
	Start time.Time `json:"start"`
	End   time.Time `json:"end"`
}

type SleepGoogle struct {
	Start         time.Time       `json:"start"`
	End           time.Time       `json:"end"`
	Asleep        *int            `json:"asleep_minutes"`
	StageMinutes  map[string]*int `json:"stage_minutes"`
	StageSegments map[string]*int `json:"stage_segments"`
	Latency       *int            `json:"minutes_to_fall_asleep"`
}

type SleepWindowInput struct {
	Google   SleepGoogle `json:"google"`
	Segments []Segment   `json:"segments"`
	Window   Span        `json:"window"`
}

type SleepWindowValues struct {
	InBed      int                     `json:"time_in_bed_minutes"`
	Asleep     *int                    `json:"asleep_minutes"`
	Efficiency *int                    `json:"efficiency_pct"`
	Latency    *int                    `json:"minutes_to_fall_asleep"`
	Stages     map[string]StageSummary `json:"stages"`
	Unstaged   []Span                  `json:"unstaged"`
	Awake      int                     `json:"awake_segments"`
	Segments   []Segment               `json:"-"`
}

// ComputeSleepWindow applies scores.md §4.2a. Uncovered time at the window's
// edges is unstaged sleep, less any of it Google's total already counts. A gap
// between two segments adds nothing: Google's total has already decided it.
func ComputeSleepWindow(in SleepWindowInput) SleepWindowValues {
	w := in.Window
	out := SleepWindowValues{
		InBed: int(math.Round(w.End.Sub(w.Start).Minutes())), Asleep: in.Google.Asleep,
		Stages: map[string]StageSummary{}, Unstaged: []Span{}, Segments: []Segment{},
	}
	if w.Start.Equal(in.Google.Start) {
		out.Latency = in.Google.Latency
	}
	clipped := false
	seconds, counts := map[string]float64{}, map[string]int{}
	sleepSeconds, googleSleepSeconds := 0.0, 0.0
	for _, segment := range in.Segments {
		segment.Stage = strings.ToLower(segment.Stage)
		if sleepStage(segment.Stage) {
			googleSleepSeconds += segment.End.Sub(segment.Start).Seconds()
		}
		clipped = clipped || segment.Start.Before(w.Start) || segment.End.After(w.End)
		segment.Start, segment.End = later(segment.Start, w.Start), earlier(segment.End, w.End)
		if !segment.Start.Before(segment.End) {
			continue
		}
		out.Segments = append(out.Segments, segment)
		duration := segment.End.Sub(segment.Start).Seconds()
		seconds[segment.Stage] += duration
		counts[segment.Stage]++
		if sleepStage(segment.Stage) {
			sleepSeconds += duration
		} else if segment.Stage == "awake" && segment.Start.After(w.Start) && segment.End.Before(w.End) {
			out.Awake++
		}
	}
	sort.Slice(out.Segments, func(i, j int) bool { return out.Segments[i].Start.Before(out.Segments[j].Start) })
	if len(in.Segments) > 0 {
		cursor, gapSeconds := w.Start, 0.0
		for i, segment := range out.Segments {
			if cursor.Before(segment.Start) && i == 0 {
				out.Unstaged = append(out.Unstaged, Span{cursor, segment.Start})
			} else if cursor.Before(segment.Start) {
				gapSeconds += segment.Start.Sub(cursor).Seconds()
			}
			cursor = later(cursor, segment.End)
		}
		if cursor.Before(w.End) {
			out.Unstaged = append(out.Unstaged, Span{cursor, w.End})
		}
		edgeSeconds := 0.0
		for _, span := range out.Unstaged {
			edgeSeconds += span.End.Sub(span.Start).Seconds()
		}
		edge, gaps := minutes(edgeSeconds), minutes(gapSeconds)
		// Minutes of Google's total that no sleep segment explains lie in its
		// uncovered time: in the gaps first, then at the edges.
		unexplained := 0
		if in.Google.Asleep != nil {
			unexplained = max(0, *in.Google.Asleep-minutes(googleSleepSeconds))
		}
		inGaps := min(gaps, unexplained)
		added := edge
		if clipped {
			out.Asleep = ptr(minutes(sleepSeconds) + inGaps + edge)
		} else if out.Asleep != nil {
			added = max(0, edge-(unexplained-inGaps))
			out.Asleep = ptr(*out.Asleep + added)
		}
		out.Stages["unstaged"] = StageSummary{Minutes: &added, Segments: ptr(len(out.Unstaged))}
	} else {
		out.Stages["unstaged"] = StageSummary{}
	}
	if out.Asleep != nil && (*out.Asleep < 0 || float64(*out.Asleep) > w.End.Sub(w.Start).Minutes()) {
		out.Asleep = nil // the inputs don't reconcile with the window
	}
	for _, key := range []string{"light", "deep", "rem", "awake"} {
		stage := StageSummary{Minutes: in.Google.StageMinutes[key], Segments: in.Google.StageSegments[key]}
		if _, exists := in.Google.StageMinutes[key]; exists && clipped {
			stage.Minutes, stage.Segments = ptr(minutes(seconds[key])), ptr(counts[key])
		}
		out.Stages[key] = stage
	}
	for key, stage := range out.Stages {
		if key != "awake" && stage.Minutes != nil && out.Asleep != nil && *out.Asleep > 0 {
			stage.Percent = ptr(round(100*float64(*stage.Minutes)/float64(*out.Asleep), 1))
		}
		out.Stages[key] = stage
	}
	if out.Asleep != nil && w.End.After(w.Start) {
		out.Efficiency = ptr(int(math.Round(100 * float64(*out.Asleep) / w.End.Sub(w.Start).Minutes())))
	}
	return out
}

func sleepStage(stage string) bool {
	switch stage {
	case "light", "deep", "rem", "asleep":
		return true
	}
	return false
}

func minutes(seconds float64) int { return int(math.Round(seconds / 60)) }

func sleepWindow(s *health.Sleep) SleepWindowValues {
	if s == nil {
		return SleepWindowValues{}
	}
	return ComputeSleepWindow(sleepInput(s))
}

func sleepInput(s *health.Sleep) SleepWindowInput {
	in := SleepWindowInput{
		Google: SleepGoogle{Start: s.Interval.Start, End: s.Interval.End, Asleep: asleep(s), Latency: integer(s.Summary.MinutesToFallAsleep), StageMinutes: map[string]*int{}, StageSegments: map[string]*int{}},
		Window: Span{s.Interval.Start, s.Interval.End},
	}
	for _, stage := range s.Summary.Stages {
		key := strings.ToLower(stage.Type)
		in.Google.StageMinutes[key], in.Google.StageSegments[key] = integer(stage.Minutes), integer(stage.Count)
	}
	for _, stage := range s.Stages {
		in.Segments = append(in.Segments, Segment{stage.Start, stage.End, strings.ToLower(stage.Type)})
	}
	return in
}

func sleepAsleep(s *health.Sleep) *int { return sleepWindow(s).Asleep }

func earlier(a, b time.Time) time.Time {
	if a.Before(b) {
		return a
	}
	return b
}

func later(a, b time.Time) time.Time {
	if a.After(b) {
		return a
	}
	return b
}

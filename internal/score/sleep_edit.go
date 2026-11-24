package score

import (
	"sort"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/health"
)

type SleepEditRange struct {
	EarliestStart time.Time `json:"earliest_start"`
	LatestEnd     time.Time `json:"latest_end"`
}

type SleepEditWindow struct {
	Start     time.Time `json:"start"`
	End       time.Time `json:"end"`
	UpdatedAt time.Time `json:"updated_at"`
}

func (e *Engine) SleepEditApplies(edit activities.SleepEdit) bool {
	s := e.main[edit.Date]
	return s != nil && edit.Start.Before(s.Interval.End) && edit.End.After(s.Interval.Start)
}

func (e *Engine) sleepEdit(date string) *activities.SleepEdit {
	for _, edit := range e.SleepEdits {
		if edit.Date == date && e.SleepEditApplies(edit) {
			return &edit
		}
	}
	return nil
}

func (e *Engine) sleep(date string) *health.Sleep {
	s := e.main[date]
	edit := e.sleepEdit(date)
	if s == nil || edit == nil {
		return s
	}
	copy := *s
	copy.Interval.Start, copy.Interval.End = edit.Start, edit.End
	if !edit.Start.Equal(s.Interval.Start) {
		copy.Summary.MinutesToFallAsleep = nil
	}
	return &copy
}

func (e *Engine) sleepEditTarget(date string) (*health.Sleep, error) {
	d, err := time.Parse("2006-01-02", date)
	if err != nil || d.Format("2006-01-02") != date || date > e.DefaultDate() || date < e.add(e.DefaultDate(), 1-activities.EditHorizonDays) {
		return nil, activities.ErrNotFound
	}
	s := e.main[date]
	if s == nil || len(s.Stages) == 0 {
		return nil, activities.ErrNotFound
	}
	return s, nil
}

func (e *Engine) sleepNeighbours(date string) []Span {
	windows := []Span{}
	for day, rows := range e.points["sleep"] {
		for _, p := range rows {
			s := p.point.Sleep
			if s == nil || s == e.main[date] {
				continue
			}
			if s == e.main[day] {
				s = e.sleep(day)
			}
			windows = append(windows, Span{s.Interval.Start, s.Interval.End})
		}
	}
	for _, w := range e.effectiveWorkouts() {
		if !w.hidden {
			windows = append(windows, Span{w.Start, w.End})
		}
	}
	return windows
}

func (e *Engine) SleepEditRange(date string) *SleepEditRange {
	s, err := e.sleepEditTarget(date)
	if err != nil {
		return nil
	}
	r := SleepEditRange{
		EarliestStart: s.Interval.Start.Add(-activities.EditMaxShiftMinutes * time.Minute),
		LatestEnd:     earlier(s.Interval.End.Add(activities.EditMaxShiftMinutes*time.Minute), earlier(e.Date(date).AddDate(0, 0, 1), e.Now)),
	}
	for _, w := range e.sleepNeighbours(date) {
		if !w.End.After(s.Interval.Start) {
			r.EarliestStart = later(r.EarliestStart, w.End)
		}
		if !w.Start.Before(s.Interval.End) {
			r.LatestEnd = earlier(r.LatestEnd, w.Start)
		}
	}
	for _, w := range e.effectiveWorkouts() {
		if !w.hidden && w.Start.After(s.Interval.Start) {
			r.LatestEnd = earlier(r.LatestEnd, w.Start)
		}
	}
	return &r
}

func (e *Engine) ValidateSleepEdit(edit activities.SleepEdit) (*activities.SleepEdit, error) {
	s, err := e.sleepEditTarget(edit.Date)
	if err != nil {
		return nil, err
	}
	bad := func(field string) (*activities.SleepEdit, error) {
		return nil, &activities.EditValidationError{Field: field}
	}
	if edit.Start.IsZero() || !edit.Start.Equal(edit.Start.Truncate(time.Minute)) {
		return bad("start")
	}
	if edit.End.IsZero() || !edit.End.Equal(edit.End.Truncate(time.Minute)) || !edit.End.After(edit.Start) {
		return bad("end")
	}
	if edit.End.After(e.Now.Add(5*time.Minute)) || edit.End.In(e.loc).Format("2006-01-02") != edit.Date {
		return bad("end")
	}
	first, last := s.Interval.Start.Add(-activities.EditMaxShiftMinutes*time.Minute), s.Interval.End.Add(activities.EditMaxShiftMinutes*time.Minute)
	if edit.Start.Before(first) || edit.Start.After(last) {
		return bad("start")
	}
	if edit.End.Before(first) || edit.End.After(last) {
		return bad("end")
	}
	if !edit.Start.Before(s.Interval.End) || !edit.End.After(s.Interval.Start) {
		return bad("start")
	}
	if edit.End.Sub(edit.Start) < activities.SleepMinMinutes*time.Minute {
		return bad("duration")
	}
	for _, w := range e.sleepNeighbours(edit.Date) {
		if edit.Start.Before(w.End) && edit.End.After(w.Start) {
			if w.Start.Before(s.Interval.Start) {
				return bad("start")
			}
			return bad("end")
		}
	}
	if edit.Start.Equal(s.Interval.Start) && edit.End.Equal(s.Interval.End) {
		return nil, nil
	}
	return &edit, nil
}

func sleepOutside(s *health.Sleep, start, end time.Time) []Segment {
	out := []Segment{}
	for _, segment := range sleepInput(s).Segments {
		if segment.Start.Before(start) {
			out = append(out, Segment{segment.Start, earlier(start, segment.End), segment.Stage})
		}
		if segment.End.After(end) {
			out = append(out, Segment{later(end, segment.Start), segment.End, segment.Stage})
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Start.Before(out[j].Start) })
	return out
}

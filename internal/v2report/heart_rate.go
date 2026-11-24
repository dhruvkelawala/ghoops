package v2report

import (
	"net/url"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/score"
)

type HeartRate struct {
	Envelope
	Freshness score.Freshness `json:"freshness"`
	score.HeartRate
}

func (b *Builder) heartRate(params url.Values) (HeartRate, error) {
	var data score.HeartRate
	if date := params.Get("date"); date != "" {
		if len(params) != 1 {
			return HeartRate{}, invalidParameter("query")
		}
		if _, err := b.date(date, "date"); err != nil {
			return HeartRate{}, err
		}
		data = b.engine.HeartRateDay(date)
	} else {
		if len(params) != 2 || params.Get("start") == "" || params.Get("end") == "" {
			return HeartRate{}, invalidParameter("query")
		}
		start, err := time.Parse(time.RFC3339, params.Get("start"))
		if err != nil {
			return HeartRate{}, invalidParameter("start")
		}
		end, err := time.Parse(time.RFC3339, params.Get("end"))
		if err != nil {
			return HeartRate{}, invalidParameter("end")
		}
		start, end = start.Truncate(time.Minute), end.Truncate(time.Minute)
		if !end.After(start) {
			return HeartRate{}, invalidParameter("start")
		}
		if end.Sub(start) > activities.HeartRateMaxSpanHours*time.Hour || end.After(b.engine.Now.Add(5*time.Minute)) {
			return HeartRate{}, NewError("date_out_of_range")
		}
		data = b.engine.HeartRate(start, end)
	}
	return HeartRate{Envelope: b.envelope("heart_rate"), Freshness: b.engine.Freshness(), HeartRate: data}, nil
}

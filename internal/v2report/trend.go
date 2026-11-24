package v2report

import "math"

const (
	TrendShortDays    = 7
	TrendLongDays     = 30
	TrendShortMinDays = 4
	TrendLongMinDays  = 7
	TrendBandSD       = 0.5
)

type BriefTrend struct {
	Direction *string `json:"direction"`
	Days7     int     `json:"days_7"`
	Days30    int     `json:"days_30"`
	*BriefTrendValues
}
type BriefTrendValues struct {
	Mean7  *float64 `json:"mean_7"`
	Mean30 *float64 `json:"mean_30"`
}
type BriefTrends struct {
	Recovery BriefTrend `json:"recovery"`
	HRV      BriefTrend `json:"hrv_rmssd_ms"`
	RHR      BriefTrend `json:"resting_hr_bpm"`
	Sleep    BriefTrend `json:"sleep_performance"`
	Asleep   BriefTrend `json:"asleep_minutes"`
	Strain   BriefTrend `json:"strain"`
}

func briefTrends(rows []DayRow, values bool) BriefTrends {
	metrics := [6][]*float64{}
	for _, row := range rows {
		var asleep *float64
		if row.Asleep != nil {
			asleep = ptr(float64(*row.Asleep))
		}
		strain := row.Strain
		if row.CycleStatus != "closed" {
			strain = nil
		}
		for i, value := range []*float64{row.Recovery, row.HRV, row.RHR, row.Performance, asleep, strain} {
			metrics[i] = append(metrics[i], value)
		}
	}
	return BriefTrends{
		Recovery: briefTrend(metrics[0], values), HRV: briefTrend(metrics[1], values),
		RHR: briefTrend(metrics[2], values), Sleep: briefTrend(metrics[3], values),
		Asleep: briefTrend(metrics[4], values), Strain: briefTrend(metrics[5], values),
	}
}

func briefTrend(rows []*float64, values bool) BriefTrend {
	out := BriefTrend{}
	if values {
		out.BriefTrendValues = &BriefTrendValues{}
	}
	var sum7, sum30 float64
	for i, value := range rows {
		if value == nil {
			continue
		}
		out.Days30++
		sum30 += *value
		if i >= len(rows)-TrendShortDays {
			out.Days7++
			sum7 += *value
		}
	}
	if out.Days7 < TrendShortMinDays || out.Days30 < TrendLongMinDays {
		return out
	}
	mean7, mean30 := sum7/float64(out.Days7), sum30/float64(out.Days30)
	var squares float64
	for _, value := range rows {
		if value != nil {
			squares += (*value - mean30) * (*value - mean30)
		}
	}
	band := TrendBandSD * math.Sqrt(squares/float64(out.Days30-1))
	direction := "near"
	if mean7-mean30 > band {
		direction = "above"
	}
	if mean7-mean30 < -band {
		direction = "below"
	}
	out.Direction = &direction
	if values {
		out.Mean7, out.Mean30 = ptr(math.Round(mean7*10)/10), ptr(math.Round(mean30*10)/10)
	}
	return out
}

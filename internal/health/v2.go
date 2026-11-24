package health

import (
	"encoding/json"
	"strings"
)

var V2Kinds = []Kind{
	{"sleep", "sleep.interval.end_time", true},
	{"daily-heart-rate-variability", "daily_heart_rate_variability.date", false},
	{"daily-resting-heart-rate", "daily_resting_heart_rate.date", false},
	{"daily-respiratory-rate", "daily_respiratory_rate.date", false},
	{"daily-oxygen-saturation", "daily_oxygen_saturation.date", false},
	{"daily-sleep-temperature-derivations", "daily_sleep_temperature_derivations.date", false},
	{"daily-heart-rate-zones", "daily_heart_rate_zones.date", false},
	{"daily-vo2-max", "daily_vo2_max.date", false},
	{"respiratory-rate-sleep-summary", "respiratory_rate_sleep_summary.sample_time.physical_time", false},
	{"heart-rate-variability", "heart_rate_variability.sample_time.physical_time", false},
	{"exercise", "exercise.interval.civil_start_time", false},
	{"irregular-rhythm-notification", "irregular_rhythm_notification.interval.start_time", false},
}

type DailyRespiratoryRate struct {
	Date Date    `json:"date"`
	BPM  *Number `json:"breathsPerMinute"`
}
type DailyOxygenSaturation struct {
	Date    Date    `json:"date"`
	Average *Number `json:"averagePercentage"`
	Lower   *Number `json:"lowerBoundPercentage"`
	Upper   *Number `json:"upperBoundPercentage"`
	SD      *Number `json:"standardDeviationPercentage"`
}
type DailyTemperature struct {
	Date     Date    `json:"date"`
	Nightly  *Number `json:"nightlyTemperatureCelsius"`
	Baseline *Number `json:"baselineTemperatureCelsius"`
	SD       *Number `json:"relativeNightlyStddev30dCelsius"`
}
type DailyHeartRateZones struct {
	Date  Date            `json:"date"`
	Zones []HeartRateZone `json:"heartRateZones"`
}
type HeartRateZone struct {
	Type string  `json:"heartRateZoneType"`
	Min  *Number `json:"minBeatsPerMinute"`
	Max  *Number `json:"maxBeatsPerMinute"`
}
type DailyVO2Max struct {
	Date      Date    `json:"date"`
	VO2       *Number `json:"vo2Max"`
	Estimated *bool   `json:"estimated"`
	Level     string  `json:"cardioFitnessLevel"`
}
type RespiratoryStats struct {
	BPM *Number `json:"breathsPerMinute"`
}
type RespiratorySleepSummary struct {
	Sample SampleTime        `json:"sampleTime"`
	Full   *RespiratoryStats `json:"fullSleepStats"`
	Deep   *RespiratoryStats `json:"deepSleepStats"`
	Light  *RespiratoryStats `json:"lightSleepStats"`
	REM    *RespiratoryStats `json:"remSleepStats"`
}
type IrregularRhythmNotification struct {
	Interval Interval `json:"interval"`
}

func DecodeV2(record Record) (Point, error) {
	_, p, err := decodeV2(record)
	return p, err
}

func decodeV2(record Record) (Record, Point, error) {
	raw, err := nullOptionalNumbers(record.Raw)
	if err != nil {
		return record, Point{}, collectionError("invalid data point")
	}
	record.Raw = raw
	p, err := Decode(record)
	if err != nil {
		switch record.Type {
		case "daily-respiratory-rate", "daily-oxygen-saturation", "daily-sleep-temperature-derivations", "daily-heart-rate-zones", "daily-vo2-max", "respiratory-rate-sleep-summary", "irregular-rhythm-notification":
			return record, p, collectionError("invalid data point")
		}
		return record, p, err
	}
	valid := true
	if p.DailyRR != nil {
		valid = inRange(p.DailyRR.BPM, 4, 60)
	}
	if p.Oxygen != nil {
		for _, n := range []*Number{p.Oxygen.Average, p.Oxygen.Lower, p.Oxygen.Upper} {
			valid = valid && inRange(n, 0, 100)
		}
		if p.Oxygen.SD != nil {
			valid = valid && inRange(p.Oxygen.SD, 0, 100)
		}
	}
	if p.Temperature != nil {
		valid = valid && inRange(p.Temperature.Nightly, 20, 45)
		if p.Temperature.Baseline != nil {
			valid = valid && inRange(p.Temperature.Baseline, 20, 45)
		}
	}
	if p.VO2 != nil {
		valid = valid && inRange(p.VO2.VO2, 0, 100)
	}
	if p.Zones != nil {
		if p.Zones.Zones == nil {
			valid = false
		}
		for _, zone := range p.Zones.Zones {
			valid = valid && inRange(zone.Min, 30, 250) && inRange(zone.Max, 30, 250)
		}
	}
	if p.RespSummary != nil {
		valid = valid && p.RespSummary.Full != nil
		if p.RespSummary.Full != nil {
			valid = valid && inRange(p.RespSummary.Full.BPM, 4, 60)
		}
		for _, stats := range []*RespiratoryStats{p.RespSummary.Deep, p.RespSummary.Light, p.RespSummary.REM} {
			if stats != nil && stats.BPM != nil {
				if *stats.BPM == 0 {
					stats.BPM = nil
					continue
				}
				valid = valid && inRange(stats.BPM, 4, 60)
			}
		}
	}
	if !valid {
		return record, p, collectionError("invalid data point")
	}
	return record, p, nil
}

func nullOptionalNumbers(raw json.RawMessage) (json.RawMessage, error) {
	var point map[string]json.RawMessage
	if err := json.Unmarshal(raw, &point); err != nil {
		return nil, err
	}
	changed := false
	for _, path := range []string{
		"dailyHeartRateVariability.averageHeartRateVariabilityMilliseconds",
		"dailyHeartRateVariability.deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds",
		"dailyHeartRateVariability.nonRemHeartRateBeatsPerMinute", "dailyHeartRateVariability.entropy",
		"heartRateVariability.rootMeanSquareOfSuccessiveDifferencesMilliseconds", "heartRateVariability.standardDeviationMilliseconds",
		"dailyOxygenSaturation.standardDeviationPercentage",
		"dailySleepTemperatureDerivations.baselineTemperatureCelsius", "dailySleepTemperatureDerivations.relativeNightlyStddev30dCelsius",
		"respiratoryRateSleepSummary.deepSleepStats.breathsPerMinute", "respiratoryRateSleepSummary.lightSleepStats.breathsPerMinute", "respiratoryRateSleepSummary.remSleepStats.breathsPerMinute",
	} {
		changed = nullNumberAt(point, strings.Split(path, ".")) || changed
	}
	if !changed {
		return raw, nil
	}
	return json.Marshal(point)
}

func nullNumberAt(object map[string]json.RawMessage, path []string) bool {
	value := object[path[0]]
	if len(path) == 1 {
		switch string(value) {
		case `"NaN"`, `"Infinity"`, `"-Infinity"`:
			object[path[0]] = json.RawMessage("null")
			return true
		}
		return false
	}
	var child map[string]json.RawMessage
	if json.Unmarshal(value, &child) != nil || !nullNumberAt(child, path[1:]) {
		return false
	}
	object[path[0]], _ = json.Marshal(child)
	return true
}

func (c *Client) RequestCount() int { return int(c.requests.Load()) }

func inRange(n *Number, lower, upper Number) bool { return n != nil && *n >= lower && *n <= upper }

func stripIRN(raw json.RawMessage) (json.RawMessage, error) {
	var point map[string]json.RawMessage
	if json.Unmarshal(raw, &point) != nil {
		return nil, collectionError("invalid data point")
	}
	var irn map[string]json.RawMessage
	if json.Unmarshal(point["irregularRhythmNotification"], &irn) != nil || irn == nil {
		return nil, collectionError("invalid data point")
	}
	delete(irn, "alertWindows")
	point["irregularRhythmNotification"], _ = json.Marshal(irn)
	return json.Marshal(point)
}

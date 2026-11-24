package v2report

import (
	"encoding/json"
	"os"
	"reflect"
	"testing"
)

func TestBriefTrendVectors(t *testing.T) {
	raw, err := os.ReadFile("../../fixtures/v2/scores/trend.json")
	if err != nil {
		t.Fatal(err)
	}
	var vectors struct {
		Cases []struct {
			Name      string     `json:"case"`
			Values    []*float64 `json:"values"`
			LastOpen  bool       `json:"last_open"`
			Direction *string    `json:"direction"`
			Days7     int        `json:"days_7"`
			Days30    int        `json:"days_30"`
			Mean7     *float64   `json:"mean_7"`
			Mean30    *float64   `json:"mean_30"`
		} `json:"cases"`
	}
	if err := json.Unmarshal(raw, &vectors); err != nil {
		t.Fatal(err)
	}
	for _, vector := range vectors.Cases {
		t.Run(vector.Name, func(t *testing.T) {
			rows := make([]DayRow, len(vector.Values))
			for i, value := range vector.Values {
				rows[i] = DayRow{CycleStatus: "closed", Recovery: value, HRV: value, RHR: value, Performance: value, Strain: value}
				if value != nil {
					rows[i].Asleep = ptr(int(*value))
				}
			}
			if vector.LastOpen {
				rows[len(rows)-1].CycleStatus = "open"
			}
			got := briefTrends(rows, true)
			metrics := []BriefTrend{got.Recovery, got.HRV, got.RHR, got.Sleep, got.Asleep, got.Strain}
			if vector.LastOpen {
				metrics = []BriefTrend{got.Strain}
			}
			want := BriefTrend{vector.Direction, vector.Days7, vector.Days30, &BriefTrendValues{vector.Mean7, vector.Mean30}}
			for i, metric := range metrics {
				if !reflect.DeepEqual(metric, want) {
					t.Fatalf("metric %d: %+v, values %+v; want %+v, values %+v", i, metric, metric.BriefTrendValues, want, want.BriefTrendValues)
				}
			}
		})
	}
}

package score

import "github.com/dhruvkelawala/ghoops/internal/config"

// Constants is contract §5.1.1 `score_constants`: the engine numbers the app shows or computes with.
type Constants struct {
	Recovery RecoveryConstants `json:"recovery"`
	Strain   StrainModel       `json:"strain"`
	Sleep    SleepConstants    `json:"sleep"`
	Workouts WorkoutOverlap    `json:"workouts"`
	Vitals   VitalConstants    `json:"vitals"`
	HRVTrend HRVTrendConstants `json:"hrv_trend"`
	Journal  JournalConstants  `json:"journal"`
}
type Band3Edges struct {
	Medium int `json:"medium"`
	High   int `json:"high"`
}
type RecoveryConstants struct {
	Bands      Band3Edges `json:"bands"`
	PenaltyMax float64    `json:"penalty_max"`
}
type StrainModel struct {
	Bands    StrainBandEdges   `json:"bands"`
	Zones    ZoneFloors        `json:"zones_hrr"`
	Trimp    TrimpCoefficients `json:"trimp"`
	Scale    StrainScale       `json:"scale"`
	Coverage CoverageCuts      `json:"coverage"`
}
type StrainBandEdges struct {
	Moderate  float64 `json:"moderate"`
	Strenuous float64 `json:"strenuous"`
	AllOut    float64 `json:"all_out"`
}
type ZoneFloors struct {
	Z1 float64 `json:"z1"`
	Z2 float64 `json:"z2"`
	Z3 float64 `json:"z3"`
	Z4 float64 `json:"z4"`
	Z5 float64 `json:"z5"`
}
type TrimpCoefficients struct {
	A float64 `json:"a"`
	B float64 `json:"b"`
}
type StrainScale struct {
	K        float64 `json:"k"`
	TrimpCap float64 `json:"trimp_cap"`
}
type CoverageCuts struct {
	Medium float64 `json:"medium"`
	High   float64 `json:"high"`
}
type SleepConstants struct {
	UnstagedCountsAs string     `json:"unstaged_counts_as"`
	Performance      Band3Edges `json:"performance_bands"`
	Consistency      Band3Edges `json:"consistency_bands"`
	Efficiency       Band3Edges `json:"efficiency_bands"`
	// Composite is present only in composite mode (composite-sleep-spec §6.2).
	Composite *CompositeConstants `json:"composite,omitempty"`
}
type CompositeConstants struct {
	Weights        CompositeWeights `json:"weights"`
	EfficiencyZero int              `json:"efficiency_zero_pct"`
	EfficiencyFull int              `json:"efficiency_full_pct"`
}
type WorkoutOverlap struct {
	Recorded float64 `json:"recorded_hidden_overlap"`
	Effort   float64 `json:"effort_hidden_overlap"`
}

type VitalConstants struct {
	RangeSD            float64 `json:"range_sd"`
	AttentionNights    int     `json:"attention_nights"`
	AttentionMinVitals int     `json:"attention_min_vitals"`
}

type HRVTrendConstants struct {
	Days        int     `json:"days"`
	MinNights   int     `json:"min_nights"`
	BandSD      float64 `json:"band_sd"`
	MinBaseline int     `json:"min_baseline"`
}

func ConstantsFor(profile string) Constants {
	a, b := trimpCoefficients(profile)
	return Constants{
		Recovery: RecoveryConstants{Bands: Band3Edges{Medium: RecoveryMediumMin, High: RecoveryHighMin}, PenaltyMax: PenaltyMax},
		Strain: StrainModel{
			Bands: StrainBandEdges{Moderate: StrainModerateMin, Strenuous: StrainStrenuousMin, AllOut: StrainAllOutMin},
			Zones: ZoneFloors{Z1: HRRFloor, Z2: Zone2HRR, Z3: Zone3HRR, Z4: Zone4HRR, Z5: Zone5HRR},
			Trimp: TrimpCoefficients{A: a, B: b}, Scale: StrainScale{K: StrainK, TrimpCap: StrainTrimpCap},
			Coverage: CoverageCuts{Medium: CoverageMedium, High: CoverageHigh},
		},
		Sleep: SleepConstants{
			UnstagedCountsAs: "asleep",
			Performance:      Band3Edges{Medium: SleepPerformanceMediumMin, High: SleepPerformanceHighMin},
			Consistency:      Band3Edges{Medium: ConsistencyMediumMin, High: ConsistencyHighMin},
			Efficiency:       Band3Edges{Medium: EfficiencyMediumMin, High: EfficiencyHighMin},
		},
		Workouts: WorkoutOverlap{Recorded: RecordedHiddenOverlap, Effort: EffortOverlap},
		Vitals:   VitalConstants{RangeSD: VitalRangeSD, AttentionNights: VitalAttentionNights, AttentionMinVitals: VitalAttentionMinVitals},
		HRVTrend: HRVTrendConstants{Days: HRVTrendDays, MinNights: HRVTrendMinNights, BandSD: HRVTrendBandSD, MinBaseline: HRVTrendMinBaseline},
		Journal:  JournalConstants{WindowDays: JournalWindowDays, MinAnswers: JournalMinAnswers},
	}
}

// ConstantsForConfig is ConstantsFor the config's TRIMP profile, plus the composite's numbers in composite mode.
func ConstantsForConfig(cfg config.Values) Constants {
	c := ConstantsFor(cfg.TrimpProfile)
	if cfg.CompositeSleep() {
		c.Sleep.Composite = &CompositeConstants{
			Weights:        CompositeWeights{Sufficiency: CompositeWeightSufficiency, Consistency: CompositeWeightConsistency, Efficiency: CompositeWeightEfficiency},
			EfficiencyZero: CompositeEfficiencyZero, EfficiencyFull: CompositeEfficiencyFull,
		}
	}
	return c
}

func trimpCoefficients(profile string) (a, b float64) {
	if profile == "banister_b167" {
		return TrimpA167, TrimpB167
	}
	return TrimpA, TrimpB
}

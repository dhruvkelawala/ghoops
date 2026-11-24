package score

import (
	"github.com/dhruvkelawala/ghoops/internal/activities"
	"time"
)

type Rating struct {
	Value  *float64 `json:"value"`
	Band   *string  `json:"band"`
	Status string   `json:"status"`
	Reason *string  `json:"reason"`
}
type Calibration struct {
	Needed int `json:"values_needed"`
	Full   int `json:"values_for_full_confidence"`
	HRV    int `json:"hrv_values"`
	RHR    int `json:"resting_hr_values"`
}
type Baseline struct {
	N     int      `json:"values_used"`
	Mean  *float64 `json:"mean"`
	SD    *float64 `json:"sd"`
	Floor *bool    `json:"sd_floor_applied"`
}
type HRVBaseline struct {
	N      int      `json:"values_used"`
	Mean   *float64 `json:"ln_mean"`
	SD     *float64 `json:"ln_sd"`
	Floor  *bool    `json:"sd_floor_applied"`
	MeanMS *float64 `json:"mean_ms"`
}
type RecoveryBaselines struct {
	Window int         `json:"window_days"`
	HRV    HRVBaseline `json:"hrv"`
	RHR    Baseline    `json:"resting_hr"`
	RR     Baseline    `json:"respiratory_rate"`
}
type RecoveryInputs struct {
	HRV   *float64 `json:"hrv_rmssd_ms"`
	RHR   *float64 `json:"resting_hr_bpm"`
	RR    *float64 `json:"respiratory_rate_bpm"`
	Temp  *float64 `json:"skin_temp_deviation_c"`
	Sleep *float64 `json:"sleep_performance"`
}
type RecoveryWeights struct {
	HRV       float64 `json:"hrv"`
	RestingHR float64 `json:"resting_hr"`
	Sleep     float64 `json:"sleep"`
}
type Components struct {
	HRVZ            float64         `json:"hrv_z"`
	HRVScore        float64         `json:"hrv_score"`
	RHRZ            float64         `json:"resting_hr_z"`
	RHRScore        float64         `json:"resting_hr_score"`
	Sleep           float64         `json:"sleep_score"`
	Base            float64         `json:"weighted_base"`
	Weights         RecoveryWeights `json:"weights"`
	RRZ             *float64        `json:"respiratory_rate_z"`
	RRPenalty       float64         `json:"respiratory_rate_penalty"`
	TempZ           *float64        `json:"skin_temp_z"`
	TempPenalty     float64         `json:"skin_temp_penalty"`
	OptionalMissing []string        `json:"optional_missing"`
}
type Recovery struct {
	Rating
	Missing     []string          `json:"missing_inputs"`
	Confidence  *string           `json:"confidence"`
	Calibrating bool              `json:"calibrating"`
	Calibration Calibration       `json:"calibration"`
	Inputs      RecoveryInputs    `json:"inputs"`
	Baseline    RecoveryBaselines `json:"baseline"`
	Components  *Components       `json:"components"`
}
type Cycle struct {
	Start       time.Time  `json:"start"`
	End         *time.Time `json:"end"`
	Status      string     `json:"status"`
	StartSource string     `json:"start_source"`
	EndSource   *string    `json:"end_source"`
}
type Zones struct {
	Below int `json:"below"`
	Z1    int `json:"z1"`
	Z2    int `json:"z2"`
	Z3    int `json:"z3"`
	Z4    int `json:"z4"`
	Z5    int `json:"z5"`
}
type Strain struct {
	Rating
	Confidence *string    `json:"confidence"`
	Trimp      *float64   `json:"trimp"`
	Coverage   *float64   `json:"hr_coverage"`
	Covered    *int       `json:"covered_minutes"`
	Expected   *int       `json:"expected_minutes"`
	Until      *time.Time `json:"coverage_until"`
	Avg        *float64   `json:"avg_hr_bpm"`
	Peak       *float64   `json:"peak_hr_bpm"`
	Rest       *float64   `json:"resting_hr_bpm"`
	RestSource *string    `json:"resting_hr_source"`
	Max        *float64   `json:"max_hr_bpm"`
	MaxSource  *string    `json:"max_hr_source"`
	Zones      *Zones     `json:"zones_minutes"`
}
type SleepNeed struct {
	Total          int      `json:"total_minutes"`
	Base           int      `json:"baseline_minutes"`
	StrainExtra    int      `json:"strain_extra_minutes"`
	DebtExtra      int      `json:"debt_extra_minutes"`
	NapCredit      int      `json:"nap_credit_minutes"`
	PreviousStrain *float64 `json:"previous_cycle_strain"`
	Nights         int      `json:"debt_nights_used"`
}
type Consistency struct {
	Rating
	Nights int      `json:"nights_used"`
	BedSD  *float64 `json:"bedtime_sd_minutes"`
	WakeSD *float64 `json:"wake_sd_minutes"`
}
type StageSummary struct {
	Minutes  *int     `json:"minutes"`
	Segments *int     `json:"segments"`
	Percent  *float64 `json:"pct_of_asleep"`
}
type Disturbances struct {
	Total int `json:"total"`
	Awake int `json:"awake_segments"`
	Short int `json:"short_awakenings"`
}
type Nap struct {
	Start  time.Time `json:"start"`
	End    time.Time `json:"end"`
	Asleep *int      `json:"asleep_minutes"`
}
type SleepSummary struct {
	StageTypical StageTypical `json:"stage_typical"`
	Performance  Rating       `json:"performance"`
	// PerformanceComposite is present only in composite mode (composite-sleep-spec D5).
	PerformanceComposite *SleepComposite         `json:"performance_composite,omitempty"`
	Asleep               *int                    `json:"asleep_minutes"`
	InBed                *int                    `json:"time_in_bed_minutes"`
	Need                 SleepNeed               `json:"need"`
	Efficiency           *int                    `json:"efficiency_pct"`
	EfficiencyBand       *string                 `json:"efficiency_band"`
	Consistency          Consistency             `json:"consistency"`
	Stages               map[string]StageSummary `json:"stages"`
	Disturbances         *Disturbances           `json:"disturbances"`
	Latency              *int                    `json:"minutes_to_fall_asleep"`
	Bedtime              *time.Time              `json:"bedtime"`
	Wake                 *time.Time              `json:"wake_time"`
	Naps                 []Nap                   `json:"naps"`
}
type StageRange struct {
	Low    *int `json:"low_minutes"`
	High   *int `json:"high_minutes"`
	Nights int  `json:"nights_used"`
}
type StageTypical struct {
	Window      int        `json:"window_nights"`
	Nights      int        `json:"nights_used"`
	Needed      int        `json:"nights_needed"`
	LowPct      int        `json:"low_percentile"`
	HighPct     int        `json:"high_percentile"`
	Light       StageRange `json:"light"`
	Deep        StageRange `json:"deep"`
	REM         StageRange `json:"rem"`
	Awake       StageRange `json:"awake"`
	Restorative StageRange `json:"restorative"`
}
type SleepSession struct {
	Google       SleepGoogle      `json:"google"`
	Edit         *SleepEditWindow `json:"edit"`
	EditRange    *SleepEditRange  `json:"edit_range"`
	Start        time.Time        `json:"start"`
	End          time.Time        `json:"end"`
	Type         *string          `json:"type"`
	Main         bool             `json:"main_sleep"`
	Processed    *bool            `json:"processed"`
	StagesStatus *string          `json:"stages_status"`
	Awake        *int             `json:"minutes_awake"`
	AfterWake    *int             `json:"minutes_after_wake_up"`
	InPeriod     *int             `json:"minutes_in_sleep_period"`
}
type RespiratoryRate struct {
	Full  *float64 `json:"full_bpm"`
	Deep  *float64 `json:"deep_bpm"`
	Light *float64 `json:"light_bpm"`
	REM   *float64 `json:"rem_bpm"`
}
type Segment struct {
	Start time.Time `json:"start"`
	End   time.Time `json:"end"`
	Stage string    `json:"stage"`
}
type Hypnogram struct {
	Outside  []Segment `json:"outside"`
	Unstaged []Span    `json:"unstaged"`
	Start    time.Time `json:"start"`
	End      time.Time `json:"end"`
	Segments []Segment `json:"segments"`
	Short    []Segment `json:"short_awakenings"`
}
type HRPoint struct {
	T   time.Time `json:"t"`
	BPM int       `json:"bpm"`
}
type HRVPoint struct {
	T     time.Time `json:"t"`
	RMSSD float64   `json:"rmssd_ms"`
}
type SleepDetail struct {
	SleepSummary
	Session     *SleepSession    `json:"session"`
	Respiratory *RespiratoryRate `json:"respiratory_rate"`
	Hypnogram   *Hypnogram       `json:"hypnogram"`
	HR          []HRPoint        `json:"overnight_hr"`
	HRV         []HRVPoint       `json:"overnight_hrv"`
}
type Vital struct {
	Value    *float64 `json:"value"`
	Unit     string   `json:"unit"`
	Status   string   `json:"status"`
	Low      *float64 `json:"range_low"`
	High     *float64 `json:"range_high"`
	N        *int     `json:"baseline_values"`
	Position *string  `json:"position"`
}
type Vitals struct {
	Metrics    map[string]Vital `json:"metrics"`
	Outside    []string         `json:"outside_range"`
	Adverse    []string         `json:"adverse"`
	Persistent []string         `json:"persistent"`
	WithRange  int              `json:"metrics_with_range"`
	Needed     int              `json:"values_needed"`
	State      string           `json:"monitor_state"`
	HRVTrend   HRVTrend         `json:"hrv_trend"`
}

// HRVTrend is scores.md §5.3: a VitalMetric for the 7-day ln RMSSD mean, plus the nights it used.
type HRVTrend struct {
	Vital
	Nights int `json:"nights"`
}
type Metric struct {
	Value  *float64 `json:"value"`
	Unit   string   `json:"unit"`
	Status string   `json:"status"`
	Reason *string  `json:"reason"`
}
type VO2Max struct {
	Value     *float64 `json:"value"`
	Unit      string   `json:"unit"`
	Date      *string  `json:"date"`
	Level     *string  `json:"cardio_fitness_level"`
	Estimated *bool    `json:"estimated"`
	Status    string   `json:"status"`
	Reason    *string  `json:"reason"`
}
type WorkoutProvider struct {
	Avg      *float64 `json:"avg_hr_bpm"`
	Calories *float64 `json:"calories_kcal"`
	AZM      *float64 `json:"active_zone_minutes"`
}
type WorkoutSource struct {
	Method     *string `json:"recording_method"`
	Platform   *string `json:"platform"`
	FormFactor *string `json:"form_factor"`
}
type Workout struct {
	Paused     int                `json:"paused_minutes"`
	Pauses     []activities.Pause `json:"pauses"`
	Original   *WorkoutOriginal   `json:"original"`
	Edit       *WorkoutEdit       `json:"edit"`
	Edited     bool               `json:"edited"`
	Merged     []WorkoutOriginal  `json:"merged"`
	Notes      *string            `json:"notes"`
	RPE        *int               `json:"rpe"`
	Origin     *string            `json:"origin"`
	Suggested  *WorkoutSuggestion `json:"suggested"`
	hidden     bool
	absorbedBy string
	Kind       string           `json:"kind"`
	ID         string           `json:"id"`
	Type       *string          `json:"exercise_type"`
	Name       *string          `json:"display_name"`
	Category   string           `json:"category"`
	CycleDate  string           `json:"cycle_date"`
	Start      time.Time        `json:"start"`
	End        time.Time        `json:"end"`
	Elapsed    float64          `json:"elapsed_minutes"`
	Active     *float64         `json:"active_minutes"`
	Strain     *float64         `json:"strain"`
	Trimp      *float64         `json:"trimp"`
	Coverage   *float64         `json:"hr_coverage"`
	Confidence *string          `json:"confidence"`
	Avg        *float64         `json:"avg_hr_bpm"`
	Peak       *float64         `json:"peak_hr_bpm"`
	Zones      *Zones           `json:"zones_minutes"`
	Provider   *WorkoutProvider `json:"provider"`
	Source     any              `json:"source"`
	GPS        bool             `json:"has_gps"`
	HR         *[]HRPoint       `json:"hr_series,omitempty"`
}
type Flag struct {
	Code     string `json:"code"`
	Severity string `json:"severity"`
	Message  string `json:"message"`
}
type Device struct {
	Status        string     `json:"status"`
	Name          *string    `json:"name"`
	Battery       *int       `json:"battery_level"`
	BatteryStatus *string    `json:"battery_status"`
	Sync          *time.Time `json:"last_sync_at"`
}
type Freshness struct {
	Collected      *time.Time `json:"collected_at"`
	CollectAge     *int       `json:"collect_age_minutes"`
	LastStatus     string     `json:"last_collect_status"`
	CollectorStale bool       `json:"collector_stale"`
	DeviceSync     *time.Time `json:"device_last_sync_at"`
	DeviceAge      *int       `json:"device_sync_age_minutes"`
	DeviceStale    *bool      `json:"device_stale"`
	DeviceSource   string     `json:"device_sync_source"`
}

package v2report

import (
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/collect"
	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/schedule"
	"github.com/dhruvkelawala/ghoops/internal/score"
	"github.com/dhruvkelawala/ghoops/internal/store2"
)

type Envelope struct {
	Version      int              `json:"schema_version"`
	Kind         string           `json:"kind"`
	Source       string           `json:"source"`
	ScoreVersion string           `json:"score_version,omitempty"`
	GeneratedAt  time.Time        `json:"generated_at"`
	Timezone     string           `json:"timezone"`
	Config       *config.Score    `json:"score_config,omitempty"`
	Constants    *score.Constants `json:"score_constants,omitempty"`
	Synthetic    bool             `json:"synthetic_fixture,omitempty"`
}
type Day struct {
	Envelope
	Freshness    score.Freshness         `json:"freshness"`
	Date         string                  `json:"date"`
	Current      bool                    `json:"is_current_cycle"`
	Cycle        score.Cycle             `json:"cycle"`
	Recovery     score.Recovery          `json:"recovery"`
	Strain       score.Strain            `json:"strain"`
	StrainTarget score.StrainTarget      `json:"strain_target"`
	Sleep        score.SleepSummary      `json:"sleep"`
	SleepPlan    *score.SleepPlan        `json:"sleep_plan"`
	Vitals       score.Vitals            `json:"vitals"`
	Activity     map[string]score.Metric `json:"activity"`
	Workouts     []score.Workout         `json:"workouts"`
	Strength     *int                    `json:"strength_minutes"`
	VO2          score.VO2Max            `json:"vo2_max"`
	Flags        []score.Flag            `json:"health_flags"`
	Comparison   Comparison              `json:"comparison"`
}
type Sleep struct {
	Envelope
	Freshness score.Freshness `json:"freshness"`
	Date      string          `json:"date"`
	score.SleepDetail
}
type Workouts struct {
	Envelope
	Freshness score.Freshness `json:"freshness"`
	From      string          `json:"from"`
	To        string          `json:"to"`
	Workouts  []score.Workout `json:"workouts"`
}
type DayRow struct {
	Date            string   `json:"date"`
	CycleStatus     string   `json:"cycle_status"`
	Recovery        *float64 `json:"recovery"`
	RecoveryBand    *string  `json:"recovery_band"`
	RecoveryStatus  string   `json:"recovery_status"`
	RecoveryReason  *string  `json:"recovery_reason"`
	Strain          *float64 `json:"strain"`
	StrainBand      *string  `json:"strain_band"`
	StrainStatus    string   `json:"strain_status"`
	Coverage        *float64 `json:"hr_coverage"`
	Performance     *float64 `json:"sleep_performance"`
	PerformanceBand *string  `json:"sleep_performance_band"`
	Asleep          *int     `json:"asleep_minutes"`
	Need            int      `json:"sleep_need_minutes"`
	InBed           *int     `json:"time_in_bed_minutes"`
	Efficiency      *int     `json:"efficiency_pct"`
	HRV             *float64 `json:"hrv_rmssd_ms"`
	RHR             *float64 `json:"resting_hr_bpm"`
	RR              *float64 `json:"respiratory_rate_bpm"`
	SpO2            *float64 `json:"spo2_pct"`
	Temperature     *float64 `json:"skin_temp_deviation_c"`
	Steps           *float64 `json:"steps"`
	AZM             *float64 `json:"active_zone_minutes"`
	Calories        *float64 `json:"calories_kcal"`
	Workouts        int      `json:"workouts"`
	Detected        int      `json:"detected_efforts"`
	Adverse         int      `json:"vitals_adverse"`
	Zones13         *int     `json:"zones_1_3_minutes"`
	Zones45         *int     `json:"zones_4_5_minutes"`
	Strength        *int     `json:"strength_minutes"`
	Restorative     *int     `json:"restorative_minutes"`
	Consistency     *int     `json:"sleep_consistency"`
	// PerformanceComposite is absent in default mode and a number or null in composite mode.
	PerformanceComposite **float64 `json:"sleep_performance_composite,omitempty"`
}
type Summary struct {
	Mean *float64 `json:"mean"`
	Min  *float64 `json:"min"`
	Max  *float64 `json:"max"`
	Days int      `json:"available_days"`
}
type Days struct {
	Envelope
	Freshness score.Freshness    `json:"freshness"`
	From      string             `json:"from"`
	To        string             `json:"to"`
	Days      []DayRow           `json:"days"`
	Summary   map[string]Summary `json:"summary"`
}
type Auth struct {
	Authorized  bool     `json:"authorized"`
	State       string   `json:"state"`
	Refreshable bool     `json:"refreshable"`
	Missing     []string `json:"missing_scopes"`
	Partial     bool     `json:"partial_permissions"`
}
type StreamStatus struct {
	Stream  string     `json:"stream"`
	Date    *string    `json:"last_date"`
	Status  string     `json:"status"`
	Success *time.Time `json:"last_success_at"`
	Error   *string    `json:"error"`
}
type Collector struct {
	Installed bool           `json:"schedule_installed"`
	Interval  int            `json:"interval_minutes"`
	Last      *store2.Run    `json:"last_run"`
	Success   *time.Time     `json:"last_core_success_at"`
	Streams   []StreamStatus `json:"streams"`
}
type StoreStatus struct {
	Oldest *string `json:"oldest_date"`
	Newest *string `json:"newest_date"`
	HRDays int     `json:"heart_rate_days"`
}
type Calibration struct {
	Status string `json:"status"`
	score.Calibration
}
type UserResource struct {
	Status  string     `json:"status"`
	Fetched *time.Time `json:"fetched_at"`
	*IRNProfile
}
type IRNProfile struct {
	Onboarded *bool `json:"onboarded"`
	Enrolled  *bool `json:"enrolled"`
}
type Server struct {
	Version   string  `json:"version"`
	Revision  string  `json:"revision"`
	ProfileID *string `json:"profile_id"`
}
type Status struct {
	Envelope
	Freshness        score.Freshness         `json:"freshness"`
	Date             string                  `json:"default_date"`
	Auth             Auth                    `json:"auth"`
	Collector        Collector               `json:"collector"`
	Device           score.Device            `json:"device"`
	Store            StoreStatus             `json:"store"`
	Calibration      Calibration             `json:"calibration"`
	User             map[string]UserResource `json:"user_resources"`
	ProviderTimezone *string                 `json:"provider_timezone"`
	Server           Server                  `json:"server"`
	EditLimits       activities.Limits       `json:"edit_limits"`
}
type Snapshot struct {
	Envelope
	Freshness score.Freshness `json:"freshness"`
	Date      string          `json:"default_date"`
	Status    Status          `json:"status"`
	Day       Day             `json:"day"`
	Sleep     Sleep           `json:"sleep"`
	Days      Days            `json:"days"`
	Workouts  Workouts        `json:"workouts"`
	Journal   Journal         `json:"journal"`
}
type BriefFreshness struct {
	Collected      *time.Time `json:"collected_at"`
	CollectorStale bool       `json:"collector_stale"`
	DeviceStale    *bool      `json:"device_stale"`
}
type BriefRecovery struct {
	Status      string  `json:"status"`
	Reason      *string `json:"reason"`
	Band        *string `json:"band"`
	Calibrating bool    `json:"calibrating"`
	*BriefRecoveryValues
}
type BriefRecoveryValues struct {
	Value *float64 `json:"value"`
}
type BriefStrain struct {
	Status     string  `json:"status"`
	Reason     *string `json:"reason"`
	Band       *string `json:"band"`
	Confidence *string `json:"confidence"`
	*BriefStrainValues
}
type BriefStrainValues struct {
	Value    *float64 `json:"value"`
	Coverage *float64 `json:"hr_coverage"`
}
type BriefSleep struct {
	Status string  `json:"status"`
	Reason *string `json:"reason"`
	Band   *string `json:"band"`
	*BriefSleepValues
}
type BriefSleepValues struct {
	Performance *float64 `json:"performance"`
	Asleep      *int     `json:"asleep_minutes"`
	Need        int      `json:"need_minutes"`
}
type BriefWorkout struct {
	Kind      string  `json:"kind"`
	Category  string  `json:"category"`
	Type      *string `json:"exercise_type"`
	Suggested *string `json:"suggested_exercise_type"`
	*BriefWorkoutValues
}
type BriefWorkoutValues struct {
	Elapsed float64  `json:"elapsed_minutes"`
	Strain  *float64 `json:"strain"`
}
type Brief struct {
	Envelope
	Disclosure string         `json:"disclosure"`
	Part       string         `json:"part"`
	Date       string         `json:"date"`
	Freshness  BriefFreshness `json:"freshness"`
	Recovery   BriefRecovery  `json:"recovery"`
	Strain     BriefStrain    `json:"strain"`
	Target     BriefTarget    `json:"strain_target"`
	Sleep      BriefSleep     `json:"sleep"`
	Plan       *BriefPlan     `json:"sleep_plan"`
	Trend      BriefTrends    `json:"trend"`
	Adverse    []string       `json:"vitals_adverse"`
	HRVTrend   BriefHRVTrend  `json:"hrv_trend"`
	Workouts   []BriefWorkout `json:"workouts"`
	Flags      []string       `json:"health_flags"`
	Week       *BriefWeek     `json:"week,omitempty"`
	Review     *BriefReview   `json:"review,omitempty"`
	Note       string         `json:"note"`
}
type Config struct {
	Envelope
	Values   config.Values `json:"values"`
	Defaults config.Values `json:"defaults"`
	Path     string        `json:"path"`
}
type Collect struct {
	collect.Result
	Synthetic bool `json:"synthetic_fixture,omitempty"`
}
type Pair struct {
	Envelope
	Paired bool `json:"paired"`
}
type PairRedeem struct {
	Envelope
	DeviceID         string    `json:"device_id"`
	Credential       string    `json:"credential"`
	VerificationCode string    `json:"verification_code"`
	MacName          string    `json:"mac_name"`
	ProfileID        string    `json:"profile_id"`
	ExpiresAt        time.Time `json:"expires_at"`
}
type PairStatus struct {
	Envelope
	DeviceID string `json:"device_id"`
	State    string `json:"state"`
}
type PairDevices struct {
	Envelope
	Devices []PairedDevice `json:"devices"`
}
type PairedDevice struct {
	ID       string     `json:"id"`
	Name     string     `json:"name"`
	State    string     `json:"state"`
	Created  time.Time  `json:"created_at"`
	Approved *time.Time `json:"approved_at"`
}
type Schedule struct {
	Envelope
	Profile string           `json:"profile"`
	Agents  []schedule.Agent `json:"agents"`
}
type Export struct {
	Envelope
	Exported  string `json:"exported"`
	ID        string `json:"id"`
	Path      string `json:"path"`
	Bytes     int    `json:"bytes"`
	Plaintext bool   `json:"plaintext_export"`
}

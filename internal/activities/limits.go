package activities

// Limits is contract §5.11 edit_limits: the request limits for the phone's edit controls.
type Limits struct {
	SleepMinMinutes         int    `json:"sleep_min_minutes"`
	HorizonDays             int    `json:"horizon_days"`
	ShiftMinutes            int    `json:"shift_minutes"`
	MergeGapMinutes         int    `json:"merge_gap_minutes"`
	MergeMaxIDs             int    `json:"merge_max_ids"`
	NotesMaxChars           int    `json:"notes_max_chars"`
	ActiveMinMinutes        int    `json:"active_min_minutes"`
	ActiveMaxMinutes        int    `json:"active_max_minutes"`
	HeartRateSpanMaxMinutes int    `json:"heart_rate_span_max_minutes"`
	RPEScale                string `json:"rpe_scale"`
}

// ReportedLimits returns the constants the validators use.
func ReportedLimits() Limits {
	return Limits{
		SleepMinMinutes: SleepMinMinutes,
		HorizonDays:     EditHorizonDays, ShiftMinutes: EditMaxShiftMinutes,
		MergeGapMinutes: MergeMaxGapMinutes, MergeMaxIDs: MaxMergeIDs,
		NotesMaxChars: NotesMaxRunes, ActiveMinMinutes: ActiveMinMinutes,
		ActiveMaxMinutes: ActiveMaxMinutes, HeartRateSpanMaxMinutes: HeartRateMaxSpanHours * 60,
		RPEScale: RPEScale,
	}
}

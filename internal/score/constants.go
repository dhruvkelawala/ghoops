package score

const (
	VitalRangeSD              = 1.25
	VitalAttentionNights      = 2
	VitalAttentionMinVitals   = 2
	SpO2FlagSD                = 2.0
	HRVTrendDays              = 7
	HRVTrendMinNights         = 4
	HRVTrendBandSD            = 1.0
	HRVTrendMinBaseline       = 14
	StageTypicalNights        = 30
	StageTypicalMinNights     = 7
	StageTypicalLowQuantile   = 0.25
	StageTypicalHighQuantile  = 0.75
	ComparisonDays            = 30
	ComparisonMinDays         = 7
	Version                   = "2.4.1"
	BaselineWindowDays        = 42
	BaselineMaxValues         = 28
	BaselineMinValues         = 7
	CalibratedValues          = 14
	SDFloorLnRMSSD            = 0.10
	SDFloorRestingHR          = 2.0
	SDFloorRespRate           = 0.4
	SDFloorSpO2               = 0.5
	SDFloorSkinTemp           = 0.10
	ZClamp                    = 3.0
	WeightHRV                 = 0.55
	WeightRestingHR           = 0.20
	WeightSleep               = 0.25
	PenaltySlope              = 5.0
	PenaltyMax                = 10.0
	RecoveryHighMin           = 67
	RecoveryMediumMin         = 34
	TrimpA                    = 0.64
	TrimpB                    = 1.92
	TrimpA167                 = 0.86
	TrimpB167                 = 1.67
	Zone2HRR                  = 0.50
	Zone3HRR                  = 0.60
	Zone4HRR                  = 0.70
	Zone5HRR                  = 0.85
	StrainModerateMin         = 10.0
	StrainStrenuousMin        = 14.0
	StrainAllOutMin           = 18.0
	SleepPerformanceHighMin   = 85
	SleepPerformanceMediumMin = 70
	ConsistencyHighMin        = 80
	ConsistencyMediumMin      = 60
	EfficiencyHighMin         = 90
	EfficiencyMediumMin       = 85
	RecordedHiddenOverlap     = 0.5
	HRRFloor                  = 0.30
	StrainK                   = 10.0
	StrainTrimpCap            = 700.0
	CoverageHigh              = 0.80
	CoverageMedium            = 0.50
	TypicalWakeDays           = 14
	TypicalWakeMinNights      = 3
	TypicalWakeDefaultMinutes = 420
	EffortHRR                 = 0.50
	EffortMinMinutes          = 10
	EffortMaxGap              = 2
	EffortOverlap             = 0.5
	SleepBaseNeedMinutes      = 450
	StrainExtraPerPoint       = 4.0
	StrainExtraFrom           = 10.0
	StrainExtraMax            = 45
	DebtFactor                = 0.25
	DebtNights                = 3
	DebtMax                   = 60
	NapCreditMax              = 120
	NeedMin                   = 300
	NeedMax                   = 720
	ConsistencyNights         = 7
	ConsistencyMinNights      = 4
	ConsistencyZeroSD         = 120.0
	CollectorStaleMinutes     = 90
	DeviceStaleMinutes        = 360
)

const (
	StrainTargetBase            = 6.0
	StrainTargetPerRecovery     = 0.12
	StrainTargetHalfWidth       = 1.5
	StrainTargetRestoreOffset   = -3.0
	StrainTargetOverreachOffset = 2.0
)

// Composite Sleep Performance (scores.md §4.5a), used only when sleep_score_mode is composite.
const (
	CompositeWeightSufficiency = 0.70
	CompositeWeightConsistency = 0.15
	CompositeWeightEfficiency  = 0.15
	CompositeEfficiencyZero    = 70
	CompositeEfficiencyFull    = 90
	CompositeRevision          = "composite.1"
)

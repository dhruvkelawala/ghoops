package score

type StrainTarget struct {
	Low      *float64 `json:"low"`
	High     *float64 `json:"high"`
	Intent   string   `json:"intent"`
	Position *string  `json:"position"`
	Status   string   `json:"status"`
	Reason   *string  `json:"reason"`
}

func StrainTargetFor(recovery Recovery, strain Strain, intent string) StrainTarget {
	target := StrainTarget{Intent: intent, Status: recovery.Status, Reason: recovery.Reason}
	if recovery.Value != nil {
		offset := 0.0
		switch intent {
		case "restore":
			offset = StrainTargetRestoreOffset
		case "overreach":
			offset = StrainTargetOverreachOffset
		}
		centre := StrainTargetBase + StrainTargetPerRecovery*(*recovery.Value) + offset
		target.Low = ptr(round(clamp(centre-StrainTargetHalfWidth, 0, 21), 1))
		target.High = ptr(round(clamp(centre+StrainTargetHalfWidth, 0, 21), 1))
		target.Status, target.Reason = "ok", nil
	}
	if strain.Confidence != nil && *strain.Confidence == "low" {
		target.Reason = ptr("low_coverage")
		return target
	}
	if target.Low != nil && strain.Value != nil {
		position := "within"
		if *strain.Value < *target.Low {
			position = "below"
		} else if *strain.Value > *target.High {
			position = "above"
		}
		target.Position = &position
	}
	return target
}

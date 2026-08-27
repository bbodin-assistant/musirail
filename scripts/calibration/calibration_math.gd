class_name CalibrationMath
extends RefCounted

const MINIMUM_OUTLIER_WINDOW_SECONDS: float = 0.040
const MAD_MULTIPLIER: float = 3.0


static func filtered_median(samples: Array[float]) -> Dictionary:
	if samples.is_empty():
		return {
			"median": 0.0,
			"used_count": 0,
			"discarded_count": 0,
			"used_mask": [],
		}

	var center: float = _median(samples)
	var deviations: Array[float] = []
	for sample: float in samples:
		deviations.append(absf(sample - center))

	var mad: float = _median(deviations)
	var outlier_window: float = maxf(
		MINIMUM_OUTLIER_WINDOW_SECONDS,
		MAD_MULTIPLIER * mad
	)
	var filtered: Array[float] = []
	var used_mask: Array[bool] = []
	for sample: float in samples:
		var is_used: bool = absf(sample - center) <= outlier_window
		used_mask.append(is_used)
		if is_used:
			filtered.append(sample)

	return {
		"median": _median(filtered),
		"used_count": filtered.size(),
		"discarded_count": samples.size() - filtered.size(),
		"used_mask": used_mask,
	}


static func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0

	var sorted_values: Array[float] = values.duplicate()
	sorted_values.sort()
	var middle: int = sorted_values.size() / 2
	if sorted_values.size() % 2 == 1:
		return sorted_values[middle]
	return (sorted_values[middle - 1] + sorted_values[middle]) / 2.0

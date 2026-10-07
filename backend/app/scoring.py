from dataclasses import dataclass


@dataclass(frozen=True)
class ScoreSignals:
    obscurity: float
    uniqueness: float
    localness: float
    visual_history: float
    community_value: float
    detour_quality: float
    tourist_penalty: float
    legal_access: bool = True


def _clamp(value: float, low: float = 0.0, high: float = 100.0) -> float:
    return max(low, min(high, value))


def anti_tourist_score(s: ScoreSignals) -> float:
    """Return 0..100. Unsafe/private-access candidates are rejected with score 0."""
    if not s.legal_access:
        return 0.0

    positive = (
        0.30 * _clamp(s.obscurity)
        + 0.20 * _clamp(s.uniqueness)
        + 0.15 * _clamp(s.localness)
        + 0.15 * _clamp(s.visual_history)
        + 0.10 * _clamp(s.community_value)
        + 0.10 * _clamp(s.detour_quality)
    )
    penalty = 0.35 * _clamp(s.tourist_penalty)
    return round(_clamp(positive - penalty), 1)

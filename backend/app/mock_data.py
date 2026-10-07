from .scoring import ScoreSignals, anti_tourist_score

RAW_PLACES = [
    {
        "id": "tll-001", "name": "Forgotten industrial waterfront", "category": "industrial",
        "lat": 59.4508, "lon": 24.7327,
        "description": "A less obvious stretch of Tallinn's industrial waterfront with layered port history.",
        "signals": ScoreSignals(88, 82, 86, 80, 70, 83, 18),
        "safety_note": "Public-space viewing only; do not enter fenced or restricted areas.",
    },
    {
        "id": "tll-002", "name": "Quiet limestone viewpoint", "category": "views",
        "lat": 59.4394, "lon": 24.7940,
        "description": "A quieter viewpoint with a different city perspective than the classic Old Town lookouts.",
        "signals": ScoreSignals(76, 71, 82, 78, 72, 90, 22),
        "safety_note": None,
    },
    {
        "id": "tll-003", "name": "Small courtyard history stop", "category": "history",
        "lat": 59.4361, "lon": 24.7474,
        "description": "A compact historical stop chosen for detail and atmosphere rather than fame.",
        "signals": ScoreSignals(69, 75, 88, 84, 78, 92, 30),
        "safety_note": "Respect residents and private entrances.",
    },
    {
        "id": "tll-004", "name": "Odd local sculpture", "category": "weird",
        "lat": 59.4325, "lon": 24.7681,
        "description": "A small piece of public art that is easy to miss and makes a good surprise-route stop.",
        "signals": ScoreSignals(91, 89, 77, 74, 68, 86, 12),
        "safety_note": None,
    },
    {
        "id": "tll-005", "name": "Independent neighbourhood café", "category": "food",
        "lat": 59.4458, "lon": 24.7048,
        "description": "A neighbourhood-style food stop intended to break up the route rather than chase famous rankings.",
        "signals": ScoreSignals(72, 67, 95, 62, 82, 84, 26),
        "safety_note": None,
    },
]


def materialized_places() -> list[dict]:
    result = []
    for raw in RAW_PLACES:
        item = {k: v for k, v in raw.items() if k != "signals"}
        item["anti_tourist_score"] = anti_tourist_score(raw["signals"])
        item["legal_access"] = raw["signals"].legal_access
        result.append(item)
    return result

from fastapi import FastAPI
from .mock_data import materialized_places
from .schemas import Place, SurpriseRequest, SurpriseRoute

app = FastAPI(
    title="AntiTourist API",
    version="0.1.0",
    description="Find routes through unusual, low-tourism places.",
)


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "version": "0.1.0"}


@app.get("/api/v1/places", response_model=list[Place])
def places() -> list[dict]:
    return materialized_places()


@app.post("/api/v1/routes/surprise", response_model=SurpriseRoute)
def surprise_route(request: SurpriseRequest) -> SurpriseRoute:
    candidates = materialized_places()

    if request.interests:
        wanted = {x.lower() for x in request.interests}
        preferred = [p for p in candidates if p["category"].lower() in wanted]
        other = [p for p in candidates if p["category"].lower() not in wanted]
        candidates = preferred + other

    candidates = [p for p in candidates if p["legal_access"]]
    candidates.sort(key=lambda p: p["anti_tourist_score"], reverse=True)

    # Wildness raises the minimum hidden-gem quality, but never leaves an empty demo route.
    threshold = 45 + request.wildness * 0.25
    filtered = [p for p in candidates if p["anti_tourist_score"] >= threshold]
    if len(filtered) < 3:
        filtered = candidates

    stop_count = max(3, min(7, request.duration_minutes // 30))
    selected = filtered[:stop_count]

    return SurpriseRoute(
        city="Tallinn",
        duration_minutes=request.duration_minutes,
        mode=request.mode,
        theme="Surprise Me",
        places=[Place(**p) for p in selected],
    )

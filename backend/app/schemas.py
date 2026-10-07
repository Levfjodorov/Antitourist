from enum import Enum
from pydantic import BaseModel, Field


class TravelMode(str, Enum):
    walking = "walking"
    cycling = "cycling"
    driving = "driving"


class SurpriseRequest(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    duration_minutes: int = Field(default=120, ge=30, le=480)
    mode: TravelMode = TravelMode.walking
    interests: list[str] = Field(default_factory=list, max_length=8)
    wildness: int = Field(default=70, ge=0, le=100)


class Place(BaseModel):
    id: str
    name: str
    category: str
    lat: float
    lon: float
    description: str
    anti_tourist_score: float
    legal_access: bool = True
    safety_note: str | None = None


class SurpriseRoute(BaseModel):
    city: str
    duration_minutes: int
    mode: TravelMode
    theme: str
    places: list[Place]

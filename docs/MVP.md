# AntiTourist MVP 0.1

## Product promise

Build a route that optimizes discovery, not popularity.

## Primary flow

1. Open app.
2. Use current/start location.
3. Pick duration.
4. Pick movement mode.
5. Pick optional interests.
6. Set Wildness (0–100).
7. Tap **Surprise Me**.
8. Receive 3–7 legal-access stops.
9. Navigate one stop at a time.

## Non-goals for 0.1

- Social network
- User accounts
- Achievements
- Full worldwide coverage
- User-submitted places
- Offline maps

## Safety/access policy

A place can be visually interesting and still be excluded. The route engine should reject locations that require trespassing, cross obvious barriers, or are marked private/restricted. Urbex content is limited to lawful public access or viewing from public space.

## Next milestone

Replace mock Tallinn data with OSM/Overpass ingestion, persist POIs in PostGIS, and add real route geometry.

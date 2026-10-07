# AntiTourist Score v0.1

Base score:

- 30% obscurity
- 20% uniqueness
- 15% localness
- 15% visual/history value
- 10% community value
- 10% detour quality

Tourism penalty:

- subtract up to 35 points based on popularity/tourist saturation

Hard rule:

- legal_access == false => score 0 and exclude from routing

Future signals:

- review-count percentile
- social-media popularity trend
- distance from major tourist clusters
- chain-business detection
- visit density by time of day
- freshness/novelty decay

from app.scoring import ScoreSignals, anti_tourist_score


def test_score_rewards_hidden_places():
    hidden = ScoreSignals(95, 90, 90, 80, 80, 85, 10)
    touristy = ScoreSignals(50, 70, 60, 80, 80, 85, 95)
    assert anti_tourist_score(hidden) > anti_tourist_score(touristy)


def test_illegal_access_is_rejected():
    s = ScoreSignals(100, 100, 100, 100, 100, 100, 0, legal_access=False)
    assert anti_tourist_score(s) == 0

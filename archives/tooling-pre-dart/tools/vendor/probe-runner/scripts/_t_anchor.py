# scripts/_t_anchor.py
"""Pure stats + pre-registered verdict for the §C9-R-T-ANCHOR de-risk (spec §3).
No I/O. Separated from _url_template so URL parsing and the bar are independently testable."""


def summarize(values):
    """(min, median, max, n) of a list of bag-Jaccard scalars, or None if empty.
    median = mean of the middle two for an even count."""
    if not values:
        return None
    s = sorted(values)
    n = len(s)
    median = s[n // 2] if n % 2 else round((s[n // 2 - 1] + s[n // 2]) / 2, 10)
    return (s[0], median, s[-1], n)


def verdict(per_site):
    """Apply the §3 pre-registered bar. `per_site` = list of
    {high_t1_median: float|None, low_max: float|None, n_t1_pairs: int}.

    Conclusive site = n_t1_pairs >= 3 with both stats present. Needs >= 2 conclusive sites.
    Bar (strict, asymmetric): HIGH uses the median, LOW uses the max.
      PASS      -> clean gap AND 0.5 strictly inside it     (t_reco = 0.5)
      RE-ANCHOR -> clean gap but 0.5 outside it             (t_reco = gap midpoint)
      FAIL      -> HIGH/LOW overlap (no separating T)       (t_reco = None)
      INCONCLUSIVE -> < 2 conclusive sites                  (t_reco = None)
    Returns (decision, t_reco)."""
    conclusive = [s for s in per_site
                  if s["n_t1_pairs"] >= 3
                  and s["high_t1_median"] is not None
                  and s["low_max"] is not None]
    if len(conclusive) < 2:
        return ("INCONCLUSIVE", None)
    min_high = min(s["high_t1_median"] for s in conclusive)
    max_low = max(s["low_max"] for s in conclusive)
    if max_low >= min_high:                      # overlap -> no clean separating threshold
        return ("FAIL", None)
    if max_low < 0.5 < min_high:                 # 0.5 strictly inside the gap
        return ("PASS", 0.5)
    return ("RE-ANCHOR", round((max_low + min_high) / 2, 3))

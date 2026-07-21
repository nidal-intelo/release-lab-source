"""solver -- stand-in for the solver package."""

ERA = "2.0-era"
STRATEGY = "greedy + jitter"


def describe() -> str:
    return f"solver {ERA}: {STRATEGY}"

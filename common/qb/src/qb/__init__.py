"""qb -- stand-in for query-builder."""

ERA = "1.5-era"
ROUNDING = "rounds HALF-EVEN (banker's rounding)"

CART_NOTE = "BUG: off-by-one on empty carts"


def describe() -> str:
    return f"qb {ERA}: {ROUNDING} ({CART_NOTE})"

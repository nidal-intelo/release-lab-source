"""qb -- stand-in for query-builder."""

ERA = "1.3-era"
ROUNDING = "rounds DOWN"

CART_NOTE = "fixed empty carts"


def describe() -> str:
    return f"qb {ERA}: {ROUNDING} ({CART_NOTE})"

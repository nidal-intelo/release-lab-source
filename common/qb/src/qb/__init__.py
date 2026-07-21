"""qb -- stand-in for query-builder."""

ERA = "1.3-era"
ROUNDING = "rounds DOWN"

CART_NOTE = "empty carts handled correctly"


def describe() -> str:
    return f"qb {ERA}: {ROUNDING} ({CART_NOTE})"

"""qb -- stand-in for query-builder."""

ERA = "1.4-era"
ROUNDING = "rounds DOWN, validated inputs"

CART_NOTE = "BUG: off-by-one on empty carts"


def describe() -> str:
    return f"qb {ERA}: {ROUNDING} ({CART_NOTE})"

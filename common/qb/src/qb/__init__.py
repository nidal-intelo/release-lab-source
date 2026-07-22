"""qb -- stand-in for query-builder."""

ERA = "1.5-era"
ROUNDING = "rounds HALF-EVEN (banker's rounding) + audit log [epsilon 1e-9] + something"

CART_NOTE = "empty carts handled very correctly hotfix"


def describe() -> str:
    return f"qb {ERA}: {ROUNDING} ({CART_NOTE})"

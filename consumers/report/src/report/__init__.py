"""report -- consumer that depends on qb and solver."""

import qb
import solver


def main() -> str:
    return f"REPORT v3: {qb.describe()} | {solver.describe()}"

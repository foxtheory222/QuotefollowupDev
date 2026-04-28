from __future__ import annotations

import sys


MESSAGE = """DEPRECATED / DO NOT EDIT.

scripts/standardize-sa1300-budget-flows.py targeted archived exported flow JSON under results/**.
It is not the authoritative Southern Alberta budget-flow generator and it does not reflect the
current self-populate fallback to the SA1300 Location Summary Month-End Plan.

Use scripts/create-southern-alberta-pilot-flow-solution.ps1 for authoritative generator changes.
If live production needs repair, use the narrow repair scripts that were updated with that generator.
"""


def main() -> int:
    sys.stderr.write(MESSAGE + "\n")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

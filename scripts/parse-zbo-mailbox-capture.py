#!/usr/bin/env python3

import argparse
import importlib.util
import json
from datetime import datetime
from pathlib import Path


def load_qfu_parser(script_path: Path):
    spec = importlib.util.spec_from_file_location("qfu_parser", script_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--capture-root", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--branches", nargs="+", default=["4171", "4172", "4173"])
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent
    qfu_parser = load_qfu_parser(repo_root / "parse-southern-alberta-workbooks.py")
    capture_root = Path(args.capture_root).resolve()
    branches = []

    for branch_code in args.branches:
        branch = dict(qfu_parser.BRANCHES[branch_code])
        branch_root = capture_root / branch_code
        if not branch_root.exists():
            raise FileNotFoundError(f"Branch capture folder not found: {branch_root}")

        backorder_path = max(branch_root.glob("*ZBO*.xlsx"), key=lambda item: item.stat().st_mtime)
        backorder_records = qfu_parser.parse_backorder_file(backorder_path, branch)

        branches.append(
            {
                "branch": branch,
                "backorders": {
                    "file_name": backorder_path.name,
                    "captured_on": datetime.fromtimestamp(backorder_path.stat().st_mtime).isoformat(),
                    "records": backorder_records,
                },
            }
        )

    payload = {
        "generated_on": datetime.now().isoformat(),
        "capture_root": str(capture_root),
        "region": {
            "region_slug": "southern-alberta",
            "region_name": "Southern Alberta",
        },
        "branches": branches,
    }

    output_path = Path(args.output).resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()

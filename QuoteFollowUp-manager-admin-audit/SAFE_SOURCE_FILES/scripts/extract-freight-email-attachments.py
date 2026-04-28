import argparse
import json
from email import policy
from email.parser import BytesParser
from pathlib import Path


def extract_attachments(source_root, output_root):
    results = []
    for eml_path in sorted(Path(source_root).rglob("*.eml")):
        branch_code = eml_path.parent.name
        with eml_path.open("rb") as handle:
            message = BytesParser(policy=policy.default).parse(handle)

        extracted = []
        for attachment in message.iter_attachments():
            filename = attachment.get_filename()
            if not filename:
                continue
            suffix = Path(filename).suffix.lower()
            if suffix not in {".xls", ".xlsx"}:
                continue
            target_dir = Path(output_root) / branch_code
            target_dir.mkdir(parents=True, exist_ok=True)
            target_path = target_dir / filename
            payload = attachment.get_payload(decode=True) or b""
            target_path.write_bytes(payload)
            extracted.append(str(target_path))

        results.append(
            {
                "email_path": str(eml_path),
                "branch_code": branch_code,
                "attachments": extracted,
            }
        )
    return results


def cli():
    parser = argparse.ArgumentParser(description="Extract freight workbook attachments from sample .eml files.")
    parser.add_argument("--source-root", required=True)
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--output-json", default="")
    args = parser.parse_args()

    result = extract_attachments(args.source_root, args.output_root)
    payload = {"source_root": str(Path(args.source_root)), "output_root": str(Path(args.output_root)), "emails": result}
    if args.output_json:
        Path(args.output_json).write_text(json.dumps(payload, ensure_ascii=True, indent=2), encoding="utf-8")
    print(json.dumps(payload, ensure_ascii=True, indent=2))


if __name__ == "__main__":
    cli()

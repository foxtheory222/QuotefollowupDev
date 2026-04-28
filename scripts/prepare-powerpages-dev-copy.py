#!/usr/bin/env python3
"""Prepare a Power Pages Enhanced export for upload into a different website.

The PAC upload command keys records by the ids inside the exported YAML. When a
target environment contains more than one website, uploading an unmodified
production export can update the wrong website. This script copies the source
site folder, remaps known source record ids to either matching target records or
fresh deterministic ids, and rewrites the website record to the intended target.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import uuid
from collections import Counter
from dataclasses import dataclass
from pathlib import Path


GUID_RE = re.compile(
    r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"
)
ENTITY_RE = re.compile(r"^([A-Za-z0-9_]+):\s*$")
RECORD_RE = re.compile(r"^-\s+RecordId:\s*(" + GUID_RE.pattern.strip(r"\b") + r")\s*$")
DISPLAY_RE = re.compile(r"^\s+DisplayName:\s*(.*)\s*$")

GENERATED_NAMESPACE = uuid.UUID("0c1c9199-cb55-4d1b-9b08-cc32f47bcf42")


@dataclass(frozen=True)
class ManifestRecord:
    entity: str
    record_id: str
    display_name: str

    @property
    def key(self) -> tuple[str, str]:
        return (self.entity.lower(), self.display_name.strip().lower())


def normalize_guid(value: str) -> str:
    return str(uuid.UUID(value)).lower()


def parse_manifest(path: Path) -> list[ManifestRecord]:
    records: list[ManifestRecord] = []
    current_entity = ""
    current_index: int | None = None

    for line in path.read_text(encoding="utf-8-sig").splitlines():
        entity_match = ENTITY_RE.match(line)
        if entity_match:
            current_entity = entity_match.group(1)
            current_index = None
            continue

        record_match = RECORD_RE.match(line)
        if record_match:
            records.append(
                ManifestRecord(
                    entity=current_entity,
                    record_id=normalize_guid(record_match.group(1)),
                    display_name="",
                )
            )
            current_index = len(records) - 1
            continue

        if current_index is not None:
            display_match = DISPLAY_RE.match(line)
            if display_match:
                raw_name = display_match.group(1).strip()
                records[current_index] = ManifestRecord(
                    entity=records[current_index].entity,
                    record_id=records[current_index].record_id,
                    display_name=raw_name.strip("'\""),
                )

    return records


def is_relationship_record(record: ManifestRecord) -> bool:
    return record.display_name.strip().startswith("$RELATIONSHIP$")


def build_forced_webrole_map(
    source_records: list[ManifestRecord],
    target_webrole_records: list[ManifestRecord],
) -> dict[str, str]:
    source_webroles = {
        record.display_name.strip().lower(): record
        for record in source_records
        if record.entity.lower() == "adx_webrole" and record.display_name
    }
    target_webroles = {
        record.display_name.strip().lower(): record
        for record in target_webrole_records
        if record.entity.lower() == "adx_webrole" and record.display_name
    }

    forced: dict[str, str] = {}
    for role_name, source in source_webroles.items():
        target = target_webroles.get(role_name)
        if target:
            forced[source.record_id] = target.record_id
    return forced


def locate_env_manifest(site_dir: Path, env_host: str | None) -> Path:
    portal_config = site_dir / ".portalconfig"
    candidates = sorted(portal_config.glob("*-manifest.yml"))
    if env_host:
        expected = portal_config / f"{env_host}-manifest.yml"
        if expected.exists():
            return expected
    if len(candidates) == 1:
        return candidates[0]
    names = ", ".join(path.name for path in candidates)
    raise SystemExit(f"Could not identify environment manifest in {portal_config}. Found: {names}")


def build_id_map(
    source_records: list[ManifestRecord],
    target_records: list[ManifestRecord],
    source_website_id: str,
    target_website_id: str,
    forced_id_map: dict[str, str] | None = None,
) -> tuple[dict[str, str], dict[str, int]]:
    source_website_id = normalize_guid(source_website_id)
    target_website_id = normalize_guid(target_website_id)

    id_map: dict[str, str] = {source_website_id: target_website_id}
    stats = Counter()
    stats["website_id_mapped"] = 1
    for source_id, target_id in (forced_id_map or {}).items():
        source_id = normalize_guid(source_id)
        target_id = normalize_guid(target_id)
        if source_id != source_website_id:
            id_map[source_id] = target_id
            stats["forced_record_ids"] += 1

    source_key_counts = Counter(
        record.key
        for record in source_records
        if record.display_name and not is_relationship_record(record)
    )
    target_key_counts = Counter(
        record.key
        for record in target_records
        if record.display_name and not is_relationship_record(record)
    )
    target_by_key = {
        record.key: record
        for record in target_records
        if record.display_name and not is_relationship_record(record) and target_key_counts[record.key] == 1
    }

    ordered_source_records = [
        record for record in source_records if not is_relationship_record(record)
    ] + [
        record for record in source_records if is_relationship_record(record)
    ]

    for source in ordered_source_records:
        if source.record_id in id_map:
            continue

        if (
            source.display_name
            and not is_relationship_record(source)
            and source_key_counts[source.key] == 1
            and target_key_counts[source.key] == 1
            and source.key in target_by_key
        ):
            id_map[source.record_id] = target_by_key[source.key].record_id
            stats["matched_existing_target_records"] += 1
            continue

        deterministic = uuid.uuid5(
            GENERATED_NAMESPACE,
            f"{source.record_id}|{target_website_id}",
        )
        id_map[source.record_id] = str(deterministic)
        stats["generated_new_record_ids"] += 1

    return id_map, dict(stats)


def copy_source_site(source_site_dir: Path, output_parent: Path, output_site_name: str) -> Path:
    output_site_dir = output_parent / output_site_name
    if output_site_dir.exists():
        shutil.rmtree(output_site_dir)
    output_parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(source_site_dir, output_site_dir)
    return output_site_dir


def rewrite_text_files(site_dir: Path, id_map: dict[str, str]) -> dict[str, int]:
    replacement_patterns = [
        (re.compile(re.escape(source_id), re.IGNORECASE), target_id)
        for source_id, target_id in sorted(id_map.items(), key=lambda item: len(item[0]), reverse=True)
    ]

    stats = Counter()
    for path in site_dir.rglob("*"):
        if not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8-sig")
        except UnicodeDecodeError:
            stats["binary_or_non_utf8_skipped"] += 1
            continue

        updated = text
        replacements = 0
        for pattern, target_id in replacement_patterns:
            updated, count = pattern.subn(target_id, updated)
            replacements += count

        if updated != text:
            path.write_text(updated, encoding="utf-8")
            stats["files_changed"] += 1
            stats["guid_replacements"] += replacements
        else:
            stats["files_unchanged"] += 1

    return dict(stats)


def update_site_identity(site_dir: Path, target_site_name: str) -> None:
    website_path = site_dir / "website.yml"
    text = website_path.read_text(encoding="utf-8")
    text = re.sub(r"^adx_name:\s*.*$", f"adx_name: {target_site_name}", text, flags=re.MULTILINE)
    website_path.write_text(text, encoding="utf-8")


def finalize_env_manifests(site_dir: Path, target_env_host: str | None, keep_env_manifest: bool) -> dict[str, list[str]]:
    removed: list[str] = []
    kept: list[str] = []
    manifests = sorted((site_dir / ".portalconfig").glob("*-manifest.yml"))
    retained_source: Path | None = manifests[0] if manifests and keep_env_manifest else None

    if retained_source and target_env_host:
        target_manifest = retained_source.parent / f"{target_env_host}-manifest.yml"
        if retained_source.name != target_manifest.name:
            if target_manifest.exists():
                target_manifest.unlink()
            retained_source.rename(target_manifest)
            retained_source = target_manifest
        kept.append(retained_source.name)

    for manifest in (site_dir / ".portalconfig").glob("*-manifest.yml"):
        if retained_source and manifest.resolve() == retained_source.resolve():
            continue
        removed.append(manifest.name)
        manifest.unlink()
    return {"removed": removed, "kept": kept}


def collect_leftover_source_ids(site_dir: Path, source_ids: set[str]) -> list[dict[str, str]]:
    leftovers: list[dict[str, str]] = []
    for path in site_dir.rglob("*"):
        if not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8-sig")
        except UnicodeDecodeError:
            continue
        lower_text = text.lower()
        for source_id in sorted(source_ids):
            if source_id in lower_text:
                leftovers.append({"file": str(path), "source_id": source_id})
                break
    return leftovers


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-site-dir", required=True, type=Path)
    parser.add_argument("--target-site-dir", required=True, type=Path)
    parser.add_argument("--output-parent", required=True, type=Path)
    parser.add_argument("--output-site-folder", required=True)
    parser.add_argument("--source-env-host", default=None)
    parser.add_argument("--target-env-host", default=None)
    parser.add_argument("--target-webrole-site-dir", default=None, type=Path)
    parser.add_argument("--keep-env-manifest", action="store_true")
    parser.add_argument("--source-website-id", required=True)
    parser.add_argument("--target-website-id", required=True)
    parser.add_argument("--target-site-name", required=True)
    parser.add_argument("--report-path", required=True, type=Path)
    args = parser.parse_args()

    source_manifest = locate_env_manifest(args.source_site_dir, args.source_env_host)
    target_manifest = locate_env_manifest(args.target_site_dir, args.target_env_host)
    source_records = parse_manifest(source_manifest)
    target_records = parse_manifest(target_manifest)
    forced_id_map: dict[str, str] = {}
    target_webrole_manifest = None
    if args.target_webrole_site_dir:
        target_webrole_manifest = locate_env_manifest(args.target_webrole_site_dir, args.target_env_host)
        forced_id_map.update(build_forced_webrole_map(source_records, parse_manifest(target_webrole_manifest)))

    id_map, map_stats = build_id_map(
        source_records=source_records,
        target_records=target_records,
        source_website_id=args.source_website_id,
        target_website_id=args.target_website_id,
        forced_id_map=forced_id_map,
    )

    output_site_dir = copy_source_site(
        source_site_dir=args.source_site_dir,
        output_parent=args.output_parent,
        output_site_name=args.output_site_folder,
    )
    rewrite_stats = rewrite_text_files(output_site_dir, id_map)
    update_site_identity(output_site_dir, args.target_site_name)
    manifest_result = finalize_env_manifests(output_site_dir, args.target_env_host, args.keep_env_manifest)

    source_ids = {record.record_id for record in source_records}
    leftovers = collect_leftover_source_ids(output_site_dir, source_ids)

    report = {
        "source_site_dir": str(args.source_site_dir),
        "target_site_dir": str(args.target_site_dir),
        "prepared_site_dir": str(output_site_dir),
        "source_manifest": str(source_manifest),
        "target_manifest": str(target_manifest),
        "target_webrole_manifest": str(target_webrole_manifest) if target_webrole_manifest else None,
        "source_record_count": len(source_records),
        "target_record_count": len(target_records),
        "id_map_count": len(id_map),
        "map_stats": map_stats,
        "rewrite_stats": rewrite_stats,
        "env_manifests": manifest_result,
        "leftover_source_ids": leftovers,
        "sample_generated_ids": [
            {"source_id": source_id, "target_id": target_id}
            for source_id, target_id in list(id_map.items())[:20]
        ],
    }

    args.report_path.parent.mkdir(parents=True, exist_ok=True)
    args.report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

    if leftovers:
        print(f"Prepared site with {len(leftovers)} leftover source-id reference(s). See {args.report_path}.")
        return 2

    print(f"Prepared site at {output_site_dir}")
    print(f"Wrote report to {args.report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

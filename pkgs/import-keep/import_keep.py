#!/usr/bin/env python3
"""Import Google Keep notes to Memos with original timestamps preserved."""

import json
import sys
import requests
from pathlib import Path
from datetime import datetime, timezone


def load_notes(folder: Path) -> list[dict]:
    """Load all JSON notes from Keep export."""
    notes = []
    for json_file in sorted(folder.glob("*.json")):
        with open(json_file) as f:
            note = json.load(f)
            note["_file"] = json_file.name
            notes.append(note)
    return notes


def format_content(note: dict) -> str:
    """Format note content with title and tags."""
    parts = []

    if note.get("title"):
        parts.append(f"# {note['title']}")
        parts.append("")

    if note.get("textContent"):
        parts.append(note["textContent"])

    if note.get("listContent"):
        for item in note["listContent"]:
            checked = "x" if item.get("isChecked") else " "
            parts.append(f"- [{checked}] {item.get('text', '')}")

    if note.get("labels"):
        tags = " ".join(f"#{label['name'].replace(' ', '_')}" for label in note["labels"])
        parts.append("")
        parts.append(tags)

    return "\n".join(parts).strip()


def usec_to_iso(usec: int) -> str:
    """Convert microseconds timestamp to ISO 8601 format."""
    return datetime.fromtimestamp(usec / 1_000_000, tz=timezone.utc).isoformat().replace("+00:00", "Z")


def create_memo(session: requests.Session, memos_url: str, content: str, created_usec: int, updated_usec: int) -> bool:
    """Create a memo via API with preserved timestamps."""
    resp = session.post(f"{memos_url}/api/v1/memos", json={"content": content})
    if resp.status_code != 200:
        print(f"  Failed to create: {resp.status_code} {resp.text}")
        return False

    memo = resp.json()
    memo_name = memo.get("name", "")

    # Update timestamps using snake_case field names
    resp = session.patch(
        f"{memos_url}/api/v1/{memo_name}",
        json={
            "name": memo_name,
            "create_time": usec_to_iso(created_usec),
            "update_time": usec_to_iso(updated_usec),
        }
    )
    if resp.status_code != 200:
        print(f"  Warning: timestamps not updated: {resp.status_code}")

    return True


def main():
    import os

    if len(sys.argv) < 3:
        print(f"Usage: MEMOS_TOKEN=... {sys.argv[0]} <memos_url> <keep_folder>")
        print(f"Example: MEMOS_TOKEN=eyJhbG... {sys.argv[0]} https://memos.example.com ~/Keep")
        sys.exit(1)

    token = os.environ.get("MEMOS_TOKEN")
    if not token:
        print("Error: MEMOS_TOKEN environment variable not set")
        sys.exit(1)

    memos_url = sys.argv[1].rstrip("/")
    keep_folder = Path(sys.argv[2]).expanduser()

    print(f"Loading notes from {keep_folder}...")
    notes = load_notes(keep_folder)

    # Filter out trashed notes
    notes = [n for n in notes if not n.get("isTrashed", False)]
    print(f"Found {len(notes)} notes (excluding trashed)")

    session = requests.Session()
    session.headers["Authorization"] = f"Bearer {token}"
    session.headers["Content-Type"] = "application/json"

    # Test connection
    resp = session.get(f"{memos_url}/api/v1/memos?pageSize=1")
    if resp.status_code != 200:
        print(f"Failed to connect: {resp.status_code} {resp.text}")
        sys.exit(1)
    print("Connected to Memos API")

    input(f"\nPress Enter to import {len(notes)} notes...")

    success = 0
    failed = 0
    skipped = 0

    for i, note in enumerate(notes, 1):
        content = format_content(note)
        if not content:
            skipped += 1
            continue

        created_usec = note.get("createdTimestampUsec", 0)
        updated_usec = note.get("userEditedTimestampUsec", created_usec)

        print(f"[{i}/{len(notes)}] {note['_file'][:40]}...", end=" ")

        if create_memo(session, memos_url, content, created_usec, updated_usec):
            print("OK")
            success += 1
        else:
            failed += 1

    print(f"\nDone: {success} imported, {failed} failed, {skipped} skipped (empty)")


if __name__ == "__main__":
    main()

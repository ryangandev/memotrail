#!/usr/bin/env python3
"""Run native UI tests signed in as a seeded, disposable local Supabase account.

The script creates a synthetic account on the local stack, seeds a small archive through
the same database functions and inserts the apps use, runs the requested UI tests with the Debug
`--review-local-session` mode, exports their screenshots, and always removes the account,
its rows, and its media. With --web it also serves the Web media API on 127.0.0.1.
"""

import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import random
import secrets
import socket
import struct
import subprocess
import tempfile
import time
from urllib.parse import quote
from urllib.request import Request, urlopen
import uuid
from zoneinfo import ZoneInfo
import zlib

from local_supabase import (
    MEDIA_BUCKET, ROOT, LocalStack, default_derived_data, exclusive_build_directory, summarize,
)

TIMEZONE = "America/Los_Angeles"


def port_open(port):
    with socket.socket() as sock:
        return sock.connect_ex(("127.0.0.1", port)) == 0


def free_port():
    """A port nothing listens on now, so concurrent runs never share the Web server's port. The
    Web runtime also reserves the port 100 above it, so both stay well inside the valid range."""
    for port in random.sample(range(31000, 32000), 1000):
        if not port_open(port) and not port_open(port + 100):
            return port
    raise RuntimeError("No free port from 31000 to 31999; set MEMOTRAIL_E2E_PORT.")


# MEMOTRAIL_E2E_PORT pins the Web server's port; without it each run picks a free one.
WEB_PORT = int(os.environ.get("MEMOTRAIL_E2E_PORT") or free_port())
if not 1 <= WEB_PORT <= 65535:
    raise ValueError("MEMOTRAIL_E2E_PORT must be a port from 1 to 65535.")
WEB_URL = f"http://127.0.0.1:{WEB_PORT}"


def wall_time(text, timezone=TIMEZONE):
    """Stores a calendar date like Web: noon wall time in the record's time zone."""
    value = datetime.fromisoformat(text + ("T12:00:00" if len(text) == 10 else ""))
    return value.replace(tzinfo=ZoneInfo(timezone)).isoformat()


def occurrence(precision="unknown", start=None, end=None, label=None):
    return {
        "p_date_precision": precision,
        "p_occurred_start": wall_time(start) if start else None,
        "p_occurred_end": wall_time(end) if end else None,
        "p_occurred_label": label,
        "p_occurred_timezone": TIMEZONE,
    }


def png(width, height, top, bottom):
    """A small synthetic gradient PNG, so a seeded photo needs no file on disk."""
    rows = []
    for y in range(height):
        mix = y / max(height - 1, 1)
        color = bytes(round(a + (b - a) * mix) for a, b in zip(top, bottom))
        rows.append(b"\x00" + color * width)

    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"".join(rows)))
            + chunk(b"IEND", b""))


def seed(stack, user):
    """A small synthetic archive covering every native screen. Nothing here is personal data.

    Entries are saved through `save_entry` like the editor, and quick captures are inserted
    like the composer's sync. It holds ordinary Entries across days and months (one with a
    photo, one with rich text, one with a Location), a closed Chapter with six Entries inside
    it and a nested Chapter, an open Chapter for Now, a First Time, a Chapter that is also a
    First Time, an undated and an approximate Entry, tags used different numbers of times, an
    Entry and a photo in Trash, and a profile name and birth date.
    """
    owner = user["owner_id"]

    def rest(path, body=None, method="POST", prefer=None):
        return stack.request(path, body, method=method, key=stack.anon_key,
                             token=user["access_token"], prefer=prefer)

    def rpc(name, **params):
        return rest("/rest/v1/rpc/" + name, params)

    rest(f"/rest/v1/profiles?user_id=eq.{owner}",
         {"display_name": "Review Tester", "timezone": TIMEZONE, "birth_date": "1990-05-14"},
         method="PATCH")

    def save(title, body, tags=(), chapter=False, first_time=False, rich=None, location=None,
             **when):
        """Saves a new Entry like the Entry editor."""
        entry_id = str(uuid.uuid4())
        rpc("save_entry", p_entry_id=entry_id, p_expected_revision=None, p_title=title,
            p_body=body, p_body_rich=rich, p_tag_names=list(tags), p_primary_location=location,
            p_photo_location=None, p_is_chapter=chapter, p_is_first_time=first_time,
            **occurrence(**when))
        return entry_id

    def capture(title, body, day=None, metadata=None):
        """Inserts a quick capture the way the composer's sync does, with the capture's id."""
        entry_id = str(uuid.uuid4())
        rest("/rest/v1/entries", {
            "id": entry_id, "owner_id": owner, "title": title, "body": body,
            "item_kind": "entry", "item_subtype": "entry",
            "occurred_start": wall_time(day) if day else None, "occurred_end": None,
            "occurred_label": None, "date_precision": "day" if day else "unknown",
            "occurred_timezone": TIMEZONE, "client_id": "ios:" + entry_id,
            "metadata": metadata or {},
        })
        return entry_id

    def attach_photo(entry_id, name, top, bottom):
        """Uploads a synthetic original and registers it, like the photo field."""
        data = png(96, 64, top, bottom)
        attachment_id = str(uuid.uuid4())
        path = f"{owner}/{entry_id}/{attachment_id}.png"
        upload = Request(
            f"{stack.base}/storage/v1/object/{MEDIA_BUCKET}/{quote(path)}", data=data,
            method="POST", headers={
                "apikey": stack.anon_key, "Authorization": "Bearer " + user["access_token"],
                "Content-Type": "image/png", "x-upsert": "false",
            })
        with urlopen(upload, timeout=30):
            pass
        rpc("register_entry_attachment", p_entry_id=entry_id, p_attachment_id=attachment_id,
            p_object_path=path, p_original_filename=name, p_mime_type="image/png",
            p_byte_size=len(data), p_pixel_width=96, p_pixel_height=64)
        return attachment_id

    def move_to_trash(entry_id):
        """Moves an Entry to Trash at its current revision, like Move to Trash."""
        row = rest(f"/rest/v1/entries?id=eq.{entry_id}&select=revision", method="GET")[0]
        rest(f"/rest/v1/entries?id=eq.{entry_id}&revision=eq.{row['revision']}",
             {"deleted_at": datetime.now(ZoneInfo("UTC")).isoformat()}, method="PATCH")

    def span(value, *marks):
        return {"type": "text", "text": value, **({"marks": [{"type": m} for m in marks]}
                                                 if marks else {})}

    def place(key, address, city, latitude, longitude):
        """A synthetic provider Location, submitted the way Web address search saves one."""
        return {"kind": "provider", "provider": "geoapify", "providerLocationId": key,
                "formattedAddress": f"{address}, {city}, OR, United States",
                "address": address, "city": city, "region": "Oregon",
                "country": "United States", "countryCode": "us",
                "latitude": latitude, "longitude": longitude}

    # A closed Chapter with six Entries dated inside it, and a Chapter nested inside it.
    save("Living in Lisbon", "Tiled streets, late dinners, and the tram up the hill.",
         tags=["travel"], chapter=True, precision="day", start="2022-02-01", end="2022-11-30")
    save("Portuguese lessons", "Tuesday and Thursday evenings above the bakery.",
         tags=["travel"], chapter=True, precision="day", start="2022-03-01", end="2022-06-30")
    for title, body, day, tags in (
        ("First morning in Alfama", "Church bells, laundry lines, and very strong coffee.",
         "2022-02-03", ["travel"]),
        ("Tram 28 to the castle", "Standing room only, every single time.", "2022-03-12",
         ["travel"]),
        ("Ranking the custard tarts", "Twelve bakeries in, the corner one still wins.",
         "2022-04-20", ["travel"]),
        ("A night of fado", "A tiny room, candles, and a song nobody wanted to end.",
         "2022-06-11", ["travel", "music"]),
        ("Beach day in Cascais", "Cold water, warm sand, and a slow train home.", "2022-07-23",
         ["travel", "coast"]),
        ("Packing the last boxes", "The flat looks bigger empty than it ever did full.",
         "2022-11-28", ["travel"]),
    ):
        save(title, body, tags=tags, precision="day", start=day)

    # An open Chapter, which Home shows under Now.
    save("Living on Maple Street", "Sunny kitchen and a creaky staircase.", tags=["home"],
         chapter=True, precision="day", start="2024-06-01")
    # A Chapter that is also a First Time.
    save("First job at the bookshop", "Shelving, recommending, and the smell of new paper.",
         chapter=True, first_time=True, precision="month", start="2015-09-01",
         end="2018-08-31")
    # First Times, one with a Location.
    save("First sourdough loaf", "Dense, a little sour, and completely ours.", tags=["baking"],
         first_time=True, precision="day", start="2024-03-02",
         location=place("review-seed-alberta", "Alberta Street", "Portland", 45.5590,
                        -122.6450))
    save("Finished the first marathon", "Slow, happy, and soaked by the last mile.",
         tags=["running"], first_time=True, precision="day", start="2023-10-08")

    # Ordinary Entries across days and months.
    save("A quiet afternoon by the coast",
         "Low tide, warm light, and a thermos of tea on the sea wall.",
         tags=["coast", "family"], precision="day", start="2025-08-14")
    # A long Web-formatted note, so search results clamp it and offer "Read full note".
    opening = ("Low tide at six.", " We walked the whole sea wall before breakfast, counted the "
               "fishing boats coming back in, and found the cafe by the lighthouse finally open.")
    packed = ("Thermos of tea", "Two wool blankets", "The good binoculars")
    closing = ("By noon the fog had lifted and the whole bay turned silver. We stayed until the "
               "last ferry and promised to come back before the summer ended.")
    letter = "\n".join(["".join(opening), *packed, closing])
    save("Letters from the coast house", letter, tags=["coast"], precision="day",
         start="2025-08-16", rich={
             "version": 1, "text": letter, "document": {"type": "doc", "content": [
                 {"type": "paragraph",
                  "content": [span(opening[0], "bold"), span(opening[1])]},
                 {"type": "bulletList", "content": [
                     {"type": "listItem", "content": [
                         {"type": "paragraph", "content": [span(item)]}]}
                     for item in packed]},
                 {"type": "paragraph", "content": [span(closing, "italic")]}]}})
    save("Evening walk by the river", "The same loop past the boathouse, a little later each week.",
         tags=["walks"], precision="month", start="2026-04-01",
         location=place("review-seed-waterfront", "Waterfront Park", "Portland", 45.5150,
                        -122.6720))
    ferry = save("Sunset from the ferry", "Orange sky, cold wind, and the whole crew on deck.",
                 tags=["family"], precision="day", start="2026-09-02")
    attach_photo(ferry, "ferry-sunset.png", (247, 160, 94), (92, 70, 140))
    removed_photo = attach_photo(ferry, "ferry-blurry.png", (120, 120, 130), (60, 60, 70))
    # An undated Entry and an approximate one.
    capture(None, "Waiting for a little context")
    save("Grandmother's recipe cards",
         "A shoebox of index cards, most of them stained with butter.", tags=["family"],
         precision="approximate", start="1998-01-01", label="Late 1990s")
    # Quick captures, the newest saved this week.
    capture("Notes from the farmers market", "Peaches, basil, and a jar of local honey.",
            day="2026-10-12")
    capture("Rainy Sunday pancakes", "Blueberries in half of them, chocolate in the rest.",
            day="2026-10-18")
    # A Web-formatted list, which the native editor keeps untouched.
    items = [{"type": "listItem", "content": [{"type": "paragraph", "content": [
        {"type": "text", "text": item}]}]} for item in ("Tent", "Stove")]
    capture("Weekend packing list", "Tent\nStove", day="2026-10-16", metadata={"body_rich": {
        "version": 1, "text": "Tent\nStove",
        "document": {"type": "doc", "content": [{"type": "bulletList", "content": items}]}}})

    # An Entry and a photo in Trash.
    move_to_trash(capture("Duplicate grocery note", "Milk, eggs, bread.", day="2026-10-10"))
    rpc("trash_entry_attachment", p_attachment_id=removed_photo)


def start_web():
    if port_open(WEB_PORT):
        raise RuntimeError(f"Port {WEB_PORT} is in use; choose another MEMOTRAIL_E2E_PORT.")
    server = subprocess.Popen(
        ["node", "scripts/e2e-server.mjs"], cwd=ROOT / "apps/web",
        env={**os.environ, "MEMOTRAIL_E2E_PORT": str(WEB_PORT)},
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    for _ in range(90):
        if server.poll() is not None:
            raise RuntimeError("The local Web server exited before becoming healthy.")
        try:
            with urlopen(WEB_URL + "/api/health", timeout=5):
                return server
        except OSError:
            time.sleep(2)
    server.terminate()
    raise RuntimeError("The local Web server did not become healthy.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator-id", required=True)
    parser.add_argument("--only-testing", action="append",
                        help="Test identifier; defaults to MemoTrailUITests/LocalSessionUITests")
    parser.add_argument("--derived-data", default=default_derived_data())
    parser.add_argument("--attachments", help="Export screenshots and recordings here")
    parser.add_argument("--web", action="store_true", help="Serve the Web media API locally")
    parser.add_argument("--dump-entries", action="store_true",
                        help="Print the synthetic account's Entries after the tests")
    args = parser.parse_args()
    stack = LocalStack()
    web = start_web() if args.web else None
    try:
        with exclusive_build_directory(args.derived_data), \
                stack.disposable_user("native-review") as user, \
                tempfile.TemporaryDirectory(prefix="memotrail-native-review-") as folder:
            seed(stack, user)
            config = Path(folder) / "session.json"
            config.write_text(json.dumps({
                "supabaseURL": stack.base, "publishableKey": stack.anon_key,
                "accessToken": user["access_token"], "refreshToken": user["refresh_token"],
                "ownerID": user["owner_id"], "email": user["email"], "name": "Review Tester",
                "apiURL": WEB_URL if web else None,
            }))
            config.chmod(0o600)
            result_bundle = Path(args.derived_data) / "Logs" / "Test" / (
                "NativeReview-" + secrets.token_hex(6) + ".xcresult")
            command = [
                "xcodebuild", "-quiet", "-project", "apps/ios/MemoTrail.xcodeproj",
                "-scheme", "MemoTrailUI", "-configuration", "Debug",
                "-destination", "platform=iOS Simulator,id=" + args.simulator_id,
                "-derivedDataPath", args.derived_data, "-parallel-testing-enabled", "NO",
                "-collect-test-diagnostics", "never", "-resultBundlePath", str(result_bundle),
                "CODE_SIGNING_ALLOWED=NO", "test",
            ]
            for test in args.only_testing or ["MemoTrailUITests/LocalSessionUITests"]:
                command.append("-only-testing:" + test)
            log = result_bundle.with_suffix(".log")
            log.parent.mkdir(parents=True, exist_ok=True)
            print("Running native UI tests as a seeded disposable local account.", flush=True)
            env = dict(os.environ, TEST_RUNNER_MEMOTRAIL_REVIEW_SESSION=str(config))
            with log.open("w") as output:
                result = subprocess.run(command, cwd=ROOT, env=env, stdout=output,
                                        stderr=subprocess.STDOUT)
            summary = summarize(result_bundle)
            if args.dump_entries:
                rows = stack.request(
                    "/rest/v1/entries?select=title,body,item_subtype,is_first_time,"
                    "date_precision,occurred_start,occurred_end,metadata"
                    "&deleted_at=is.null&order=created_at",
                    method="GET", key=stack.anon_key, token=user["access_token"])
                print(json.dumps(rows, indent=2, ensure_ascii=False), flush=True)
            if args.attachments:
                subprocess.run([
                    "xcrun", "xcresulttool", "export", "attachments", "--path",
                    str(result_bundle), "--output-path", args.attachments,
                ], check=False, stdout=subprocess.DEVNULL)
                print("Attachments:", args.attachments, flush=True)
            print("Native UI test exit code:", result.returncode, "Log:", log, flush=True)
            return result.returncode or (1 if summary["skippedTests"] or not summary["passedTests"] else 0)
    finally:
        if web:
            os.killpg(web.pid, 15)


if __name__ == "__main__":
    raise SystemExit(main())

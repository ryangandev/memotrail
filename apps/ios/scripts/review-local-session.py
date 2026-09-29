#!/usr/bin/env python3
"""Run native UI tests signed in as a seeded, disposable local Supabase account.

The script creates a synthetic account on the local stack, seeds a small archive through
the same database functions the apps use, runs the requested UI tests with the Debug
`--review-local-session` mode, exports their screenshots, and always removes the account,
its rows, and its media. With --web it also serves the Web media API on 127.0.0.1.
"""

import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import tempfile
import time
from urllib.request import urlopen
from zoneinfo import ZoneInfo

from local_supabase import ROOT, LocalStack, summarize

TIMEZONE = "America/Los_Angeles"
WEB_URL = "http://127.0.0.1:3100"


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


def seed(stack, user):
    """A small synthetic archive covering the native screens. Nothing here is personal data."""
    owner = user["owner_id"]

    def rest(path, body, method="POST", prefer=None):
        return stack.request(path, body, method=method, key=stack.anon_key,
                             token=user["access_token"], prefer=prefer)

    def rpc(name, **params):
        return rest("/rest/v1/rpc/" + name, params)

    rest(f"/rest/v1/profiles?user_id=eq.{owner}",
         {"display_name": "Review Tester", "timezone": TIMEZONE}, method="PATCH")

    def capture(title, body):
        return rest("/rest/v1/entries", {
            "owner_id": owner, "title": title, "body": body, "inbox_status": "unreviewed",
            "item_kind": "entry", "item_subtype": "entry", "date_precision": "unknown",
            "occurred_timezone": TIMEZONE, "client_id": "review:" + secrets.token_hex(8),
        }, prefer="return=representation")[0]

    def organize(title, body, collections=(), tags=(), **when):
        """Saves a capture to the Library like Inbox review's Save to Library."""
        row = capture(title, body)
        rpc("review_wiki_item_with_location_rich",
            p_entry_id=row["id"], p_expected_revision=row["revision"], p_title=title,
            p_body=body, p_item_kind="entry", p_item_subtype="entry",
            p_collection_names=list(collections), p_tag_names=list(tags), p_mark_done=True,
            p_photo_place=None, p_primary_location=None, p_body_rich=None, **occurrence(**when))

    organize("A quiet afternoon by the coast",
             "Low tide, warm light, and a thermos of tea on the sea wall.",
             collections=["Summer 2025"], tags=["coast", "family"],
             precision="day", start="2025-08-14")
    first_time = occurrence("day", "2024-03-02")
    first_time.pop("p_occurred_end")
    rpc("save_first_time_with_occurrence",
        p_title="First sourdough loaf", p_body="Dense, a little sour, and completely ours.",
        p_collection_names=["Kitchen"], p_tag_names=["baking"], p_entry_id=None,
        p_expected_revision=None, p_occurred_end=None, **first_time)
    organize("Evening walks along the river",
             "Most evenings that spring ended with the same loop past the boathouse.",
             collections=["Summer 2025"], tags=["walks"],
             precision="range", start="2025-04-01", end="2025-06-30")
    organize("Grandmother's recipe cards",
             "A shoebox of index cards, most of them stained with butter.",
             tags=["family"], precision="approximate", start="1998-01-01",
             label="Late 1990s")
    capture(None, "Waiting for a little context")
    capture("Notes from the farmers market", "Peaches, basil, and a jar of local honey.")

    tracks = stack.request(f"/rest/v1/timeline_tracks?select=id,system_key&order=sort_order",
                           method="GET", key=stack.anon_key, token=user["access_token"])
    track = next((t for t in tracks if t["system_key"] == "general"), tracks[0])["id"]
    rpc("save_timeline_entry_with_organization",
        p_track_id=track, p_timeline_kind="event", p_title="Finished the first marathon",
        p_body="Slow, happy, and soaked by the last mile.", p_collection_names=[],
        p_tag_names=["running"], p_entry_id=None, p_expected_revision=None,
        **occurrence("day", "2023-10-08"))
    rpc("save_timeline_entry_with_organization",
        p_track_id=track, p_timeline_kind="stage", p_title="Living in Lisbon",
        p_body="Tiled streets, late dinners, and the tram up the hill.",
        p_collection_names=[], p_tag_names=[], p_entry_id=None, p_expected_revision=None,
        **occurrence("range", "2022-02-01", "2022-11-30"))

    rpc("save_home_entry_with_occurrence",
        p_title="Maple Street flat", p_body="Sunny kitchen and a creaky staircase.",
        p_place_id=None, p_place_name="Maple Street flat", p_address="120 Maple Street",
        p_city="Portland", p_region="Oregon", p_country="United States",
        p_latitude=45.5231, p_longitude=-122.6765, p_place_notes=None,
        p_move_in_reason="Closer to work", p_move_out_reason=None,
        p_collection_names=[], p_tag_names=["home"], p_entry_id=None,
        p_expected_revision=None, **occurrence("range", "2021-06-01"))
    rpc("save_vehicle_entry_with_occurrence",
        p_title="Blue hatchback", p_body="Road trips, groceries, and one flat tire.",
        p_make="Honda", p_model="Fit", p_model_year=2015, p_color="Blue",
        p_collection_names=[], p_tag_names=["car"], p_entry_id=None,
        p_expected_revision=None, **occurrence("range", "2019-09-15"))
    rpc("save_goal_entry",
        p_title="Hike the coast trail", p_body="All of it, in sections, before next autumn.",
        p_horizon="short_term", p_status="active", p_target_date="2026-10-31",
        p_collection_names=[], p_tag_names=["walks"], p_related_entry_ids=[],
        p_entry_id=None, p_expected_revision=None)


def port_open(port):
    with socket.socket() as sock:
        return sock.connect_ex(("127.0.0.1", port)) == 0


def start_web():
    if port_open(3100):
        raise RuntimeError("Port 3100 is in use; stop the other local Web server first.")
    server = subprocess.Popen(
        ["node", "scripts/e2e-server.mjs"], cwd=ROOT / "apps/web",
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    for _ in range(90):
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
    parser.add_argument("--derived-data", default="/private/tmp/memotrail-ios-review-build")
    parser.add_argument("--attachments", help="Export screenshots and recordings here")
    parser.add_argument("--web", action="store_true", help="Serve the Web media API locally")
    parser.add_argument("--dump-entries", action="store_true",
                        help="Print the synthetic account's Entries after the tests")
    args = parser.parse_args()
    stack = LocalStack()
    web = start_web() if args.web else None
    try:
        with stack.disposable_user("native-review") as user, \
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
            log = Path(args.derived_data) / "native-review.log"
            log.parent.mkdir(parents=True, exist_ok=True)
            print("Running native UI tests as a seeded disposable local account.", flush=True)
            env = dict(os.environ, TEST_RUNNER_MEMOTRAIL_REVIEW_SESSION=str(config))
            with log.open("w") as output:
                result = subprocess.run(command, cwd=ROOT, env=env, stdout=output,
                                        stderr=subprocess.STDOUT)
            summary = summarize(result_bundle)
            if args.dump_entries:
                rows = stack.request(
                    "/rest/v1/entries?select=title,body,inbox_status,item_kind,item_subtype,"
                    "date_precision,metadata&deleted_at=is.null&order=created_at",
                    method="GET", key=stack.anon_key, token=user["access_token"])
                print(json.dumps(rows, indent=2, ensure_ascii=False), flush=True)
            if args.attachments:
                subprocess.run([
                    "xcrun", "xcresulttool", "export", "attachments", "--path",
                    str(result_bundle), "--output-path", args.attachments,
                ], check=False, stdout=subprocess.DEVNULL)
                print("Attachments:", args.attachments, flush=True)
            print("Native UI test exit code:", result.returncode, "Log:", log, flush=True)
            return result.returncode or (1 if summary["skippedTests"] else 0)
    finally:
        if web:
            os.killpg(web.pid, 15)


if __name__ == "__main__":
    raise SystemExit(main())

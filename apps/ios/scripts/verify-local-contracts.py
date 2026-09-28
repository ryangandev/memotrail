#!/usr/bin/env python3
"""Run native tests with a disposable account on the local Supabase stack."""

import argparse
import json
from pathlib import Path
import secrets
import subprocess
import tempfile
from urllib.parse import urlparse
from urllib.request import Request, urlopen


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator-id", required=True)
    parser.add_argument("--derived-data", default="/private/tmp/memotrail-ios-adoption-build")
    parser.add_argument("--source-packages", help="Optional existing Xcode SourcePackages directory")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    status = json.loads(subprocess.check_output(
        ["supabase", "status", "-o", "json"], cwd=root, stderr=subprocess.DEVNULL))
    base = status["API_URL"]
    if urlparse(base).hostname != "127.0.0.1":
        raise RuntimeError("Native contract tests require the local Supabase stack.")
    service_key = status["SERVICE_ROLE_KEY"]

    def request(path, body=None, *, method="POST", key=service_key):
        req = Request(base + path, method=method, headers={
            "apikey": key, "Authorization": "Bearer " + key,
            "Content-Type": "application/json",
        }, data=None if body is None else json.dumps(body).encode())
        with urlopen(req, timeout=30) as response:
            data = response.read()
            return json.loads(data) if data else None

    email = "native-contract-" + secrets.token_hex(12) + "@example.invalid"
    user = request("/auth/v1/admin/users", {
        "email": email, "email_confirm": True,
    })
    owner_id = user["id"]
    try:
        link = request("/auth/v1/admin/generate_link", {
            "type": "magiclink", "email": email,
        })
        session = request("/auth/v1/verify", {
            "type": "magiclink", "token_hash": link["hashed_token"],
        }, key=status["ANON_KEY"])
        with tempfile.TemporaryDirectory(prefix="memotrail-native-contract-") as folder:
            config = Path(folder) / "config.json"
            config.write_text(json.dumps({
                "supabaseURL": base, "publishableKey": status["ANON_KEY"],
                "accessToken": session["access_token"], "refreshToken": session["refresh_token"],
                "ownerID": owner_id,
            }))
            config.chmod(0o600)
            result_bundle = Path(args.derived_data) / "Logs" / "Test" / ("NativeContracts-" + secrets.token_hex(6) + ".xcresult")
            command = [
                "xcodebuild", "-quiet", "-project", "apps/ios/MemoTrail.xcodeproj",
                "-scheme", "MemoTrail", "-configuration", "Debug",
                "-destination", "platform=iOS Simulator,id=" + args.simulator_id,
                "-derivedDataPath", args.derived_data, "-parallel-testing-enabled", "NO",
                "-collect-test-diagnostics", "never",
                "-resultBundlePath", str(result_bundle),
                "CODE_SIGNING_ALLOWED=NO", "MEMOTRAIL_NATIVE_CONTRACT_CONFIG=" + str(config),
                "test",
            ]
            if args.source_packages:
                command.extend(["-clonedSourcePackagesDirPath", args.source_packages])
            log = Path("/private/tmp/memotrail-native-contract-tests.log")
            print("Running native tests against local Supabase with a disposable account.", flush=True)
            with log.open("w") as output:
                result = subprocess.run(command, cwd=root, stdout=output, stderr=subprocess.STDOUT)
            summary = json.loads(subprocess.check_output([
                "xcrun", "xcresulttool", "get", "test-results", "summary",
                "--path", str(result_bundle),
            ]))
            print("Tests passed:", summary["passedTests"], "failed:", summary["failedTests"],
                  "skipped:", summary["skippedTests"], flush=True)
            for failure in summary.get("testFailures", []):
                print(failure["testIdentifierString"], failure["failureText"], flush=True)
            print("Native test exit code:", result.returncode, "Log:", log, flush=True)
            return result.returncode or (1 if summary["skippedTests"] else 0)
    finally:
        request("/auth/v1/admin/users/" + owner_id, method="DELETE")
        print("Disposable local account and its owned data removed.", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Run native tests with a disposable account on the local Supabase stack."""

import argparse
import json
from pathlib import Path
import secrets
import subprocess
import tempfile

from local_supabase import ROOT, LocalStack, summarize


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator-id", required=True)
    parser.add_argument("--derived-data", default="/private/tmp/memotrail-ios-adoption-build")
    parser.add_argument("--source-packages", help="Optional existing Xcode SourcePackages directory")
    args = parser.parse_args()
    stack = LocalStack()
    with stack.disposable_user("native-contract") as user, \
            tempfile.TemporaryDirectory(prefix="memotrail-native-contract-") as folder:
        config = Path(folder) / "config.json"
        config.write_text(json.dumps({
            "supabaseURL": stack.base, "publishableKey": stack.anon_key,
            "accessToken": user["access_token"], "refreshToken": user["refresh_token"],
            "ownerID": user["owner_id"],
        }))
        config.chmod(0o600)
        result_bundle = Path(args.derived_data) / "Logs" / "Test" / (
            "NativeContracts-" + secrets.token_hex(6) + ".xcresult")
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
            result = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
        summary = summarize(result_bundle)
        print("Native test exit code:", result.returncode, "Log:", log, flush=True)
        return result.returncode or (1 if summary["skippedTests"] else 0)


if __name__ == "__main__":
    raise SystemExit(main())

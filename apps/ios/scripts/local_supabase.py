"""Disposable accounts on the local Supabase stack for native tests and review.

Every helper refuses to run unless the stack answers on 127.0.0.1, so synthetic
accounts and seed data never reach a hosted project.
"""

from contextlib import contextmanager
import fcntl
import hashlib
import json
from pathlib import Path
import secrets
import subprocess
from urllib.parse import quote, urlparse
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[3]
MEDIA_BUCKET = "entry-media"


def default_derived_data():
    workspace = hashlib.sha256(str(ROOT).encode()).hexdigest()[:12]
    return f"/private/tmp/memotrail-ios-{workspace}"


@contextmanager
def exclusive_build_directory(directory):
    """Keep simultaneous local test runs from sharing Xcode's build database."""
    folder = Path(directory)
    folder.mkdir(parents=True, exist_ok=True)
    with (folder / ".memotrail-test.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError(
                "Another native test run uses this build directory; choose a different --derived-data."
            ) from None
        yield


class LocalStack:
    def __init__(self):
        status = json.loads(subprocess.check_output(
            ["supabase", "status", "-o", "json"], cwd=ROOT, stderr=subprocess.DEVNULL))
        self.base = status["API_URL"]
        if urlparse(self.base).hostname != "127.0.0.1":
            raise RuntimeError("Native local sessions require the local Supabase stack.")
        self.anon_key = status["ANON_KEY"]
        self.service_key = status["SERVICE_ROLE_KEY"]

    def request(self, path, body=None, *, method="POST", key=None, token=None, prefer=None):
        key = key or self.service_key
        headers = {
            "apikey": key, "Authorization": "Bearer " + (token or key),
            "Content-Type": "application/json",
        }
        if prefer:
            headers["Prefer"] = prefer
        req = Request(self.base + path, method=method, headers=headers,
                      data=None if body is None else json.dumps(body).encode())
        try:
            with urlopen(req, timeout=30) as response:
                data = response.read()
                return json.loads(data) if data else None
        except HTTPError as error:
            detail = error.read().decode(errors="replace")[:500]
            raise RuntimeError(f"{method} {path.split('?')[0]} failed ({error.code}): {detail}") from None

    @contextmanager
    def disposable_user(self, prefix):
        """Yields a signed-in synthetic account, then removes it with its owned rows and media."""
        email = f"{prefix}-{secrets.token_hex(12)}@example.invalid"
        user = self.request("/auth/v1/admin/users", {"email": email, "email_confirm": True})
        owner_id = user["id"]
        try:
            link = self.request("/auth/v1/admin/generate_link", {
                "type": "magiclink", "email": email,
            })
            session = self.request("/auth/v1/verify", {
                "type": "magiclink", "token_hash": link["hashed_token"],
            }, key=self.anon_key)
            yield {
                "email": email, "owner_id": owner_id,
                "access_token": session["access_token"],
                "refresh_token": session["refresh_token"],
            }
        finally:
            removed = self._remove_media(owner_id + "/")
            self.request("/auth/v1/admin/users/" + owner_id, method="DELETE")
            print(f"Disposable local account, its owned data, and {removed} media objects removed.",
                  flush=True)

    def _remove_media(self, prefix):
        paths = []
        pending = [prefix]
        while pending:
            folder = pending.pop()
            for item in self.request(f"/storage/v1/object/list/{MEDIA_BUCKET}", {
                "prefix": folder, "limit": 1000, "offset": 0,
            }) or []:
                path = folder + item["name"]
                if item.get("id") is None:
                    pending.append(path + "/")
                else:
                    paths.append(path)
        for start in range(0, len(paths), 100):
            self.request(f"/storage/v1/object/{quote(MEDIA_BUCKET)}",
                         {"prefixes": paths[start:start + 100]}, method="DELETE")
        return len(paths)


def summarize(result_bundle):
    summary = json.loads(subprocess.check_output([
        "xcrun", "xcresulttool", "get", "test-results", "summary",
        "--path", str(result_bundle),
    ]))
    print("Tests passed:", summary["passedTests"], "failed:", summary["failedTests"],
          "skipped:", summary["skippedTests"], flush=True)
    for failure in summary.get("testFailures", []):
        print(failure["testIdentifierString"], failure["failureText"], flush=True)
    return summary

"""sync_master_d1.preflight が 403 [7403] の原因を切り分けるか。"""
import os
import unittest
from unittest import mock

import sync_master_d1 as s

ACCT = "0123456789abcdef0123456789abcdef"
OTHER = "fedcba9876543210fedcba9876543210"


def fake(responses):
    def get(path, token):
        for prefix, res in responses:
            if path.startswith(prefix):
                return res
        raise AssertionError(path)
    return get


OK_VERIFY = ("/user/tokens/verify", (200, {"success": True, "result": {"status": "active"}}))


class Preflight(unittest.TestCase):
    def run_with(self, responses, account=ACCT):
        env = {"CLOUDFLARE_API_TOKEN": "t", "CLOUDFLARE_ACCOUNT_ID": account}
        with mock.patch.dict(os.environ, env), mock.patch.object(s, "cf_get", fake(responses)), \
                mock.patch.object(s, "database_id", lambda: "db"):
            s.preflight()

    def test_ok(self):
        self.run_with([OK_VERIFY, ("/accounts?", (200, {"result": [{"id": ACCT}]})),
                       (f"/accounts/{ACCT}/d1", (200, {"success": True}))])

    def test_malformed_account(self):
        with self.assertRaisesRegex(SystemExit, "32 文字"):
            self.run_with([], account="me@example.com")

    def test_dead_token(self):
        with self.assertRaisesRegex(SystemExit, "TOKEN が通らない"):
            self.run_with([("/user/tokens/verify", (401, {})), (f"/accounts/{ACCT}/tokens", (401, {}))])

    def test_wrong_account(self):
        with self.assertRaisesRegex(SystemExit, "このトークンのアカウントではない"):
            self.run_with([OK_VERIFY, ("/accounts?", (200, {"result": [{"id": OTHER}]}))])

    def test_no_d1_permission(self):
        with self.assertRaisesRegex(SystemExit, "D1 → Edit"):
            self.run_with([OK_VERIFY, ("/accounts?", (200, {"result": [{"id": ACCT}]})),
                           (f"/accounts/{ACCT}/d1", (403, {"errors": [{"code": 7403, "message": "x"}]}))])


if __name__ == "__main__":
    unittest.main()

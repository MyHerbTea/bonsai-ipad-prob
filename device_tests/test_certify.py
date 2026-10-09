import json
from pathlib import Path
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch
from device_tests.certify import Certification, safe_id, response_json, MODEL, BUILD89_ID


class MockServer(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        if self.path == "/health":
            body = {"status": "ok", "context_window": 32768}
        elif self.path == "/v1/models":
            body = {"data": [{"id": MODEL, "context_length": 32768, "max_output_tokens": 256}]}
        elif self.path == "/debug/build":
            body = {"build_id": BUILD89_ID}
        else:
            body = {"captured_at": "2026-10-09T00:00:00Z", "phys_footprint_bytes": 10}
        self.wfile.write(json.dumps(body).encode())

    def do_POST(self):
        raw = self.rfile.read(int(self.headers["Content-Length"]))
        body = json.loads(raw)
        assert "Authorization" in self.headers
        assert self.headers["X-Bonsai-Run-Id"]
        if body.get("stream"):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            self.wfile.write(b'data: {"choices":[{"delta":{"content":"Test"}}]}\n\n')
            self.wfile.write(b'data: [DONE]\n\n')
        else:
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            response = {"choices": [{"message": {"content": "BONSAI_P0_OK"}}],
                        "usage": {"prompt_tokens": 12, "completion_tokens": 5}}
            self.wfile.write(json.dumps(response).encode())

    def log_message(self, *_):
        return


class RunnerTests(unittest.TestCase):
    def test_ids(self):
        self.assertEqual(safe_id("run-123.abc"), "run-123.abc")
        with self.assertRaises(ValueError):
            safe_id("invalid id/with slash")
        with self.assertRaises(ValueError):
            safe_id("x" * 100)

    def test_json_shape(self):
        self.assertEqual(response_json(b'{"ok":1}')["ok"], 1)
        with self.assertRaises(ValueError):
            response_json(b'[1]')

    def test_server_contract(self):
        server = ThreadingHTTPServer(("127.0.0.1", 0), MockServer)
        t = threading.Thread(target=server.serve_forever, daemon=True)
        t.start()
        try:
            c = {"base_url": f"http://127.0.0.1:{server.server_address[1]}/v1",
                 "api_key": "SECRET_DO_NOT_PERSIST",
                 "model": MODEL, "context_window": 32768, "server_max_output_tokens": 256,
                 "build_id": BUILD89_ID}
            with tempfile.TemporaryDirectory() as d, patch.dict("os.environ", {"BONSAI_API_KEY": ""}):
                instance = Certification(c, "smoke", Path(d), timeout=15)
                self.assertEqual(instance.run(), 0)
                files = sorted(Path(d).rglob("*"))
                self.assertTrue(any(p.name == "summary.json" for p in files))
                for f in files:
                    if f.is_file() and f.suffix != ".zip":
                        self.assertNotIn("SECRET_DO_NOT_PERSIST", f.read_text())
                summary = json.loads((instance.outdir / "summary.json").read_text())
                self.assertEqual(summary["result"], "PASS")
                self.assertFalse(summary["server_side_run_request_correlation_verified"])
                self.assertFalse(summary["server_product_git_sha_verified"])
        finally:
            server.shutdown()
            t.join(timeout=2)
            server.server_close()


if __name__ == "__main__":
    unittest.main()

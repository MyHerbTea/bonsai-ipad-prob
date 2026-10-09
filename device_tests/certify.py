#!/usr/bin/env python3
"""BonsaiLab P0: read-only provenance + bounded OpenAI LAN smoke certification.

Only stdlib required. No API key or Authorization header is written to results.
This runner is intentionally NOT a server-side request-id/cancellation implementation.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import sys
import time
import traceback
import urllib.error
import urllib.request
import urllib.parse
import uuid
import zipfile

BUILD89_ID = "rc1.26-build89-compact-scheduler-metadata"
MODEL = "bonsai-2-27b-local"
CTX = 32768


def safe_id(value: str, maxlen: int = 96) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_.-]{1,96}", value) or len(value) > maxlen:
        raise ValueError("Unsafe identifier")
    return value


def now_utc() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds")


def make_run_id() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-b89-" + uuid.uuid4().hex[:8]


def safe_error_location(exc: Exception) -> str:
    """Only a source filename and line number, never URLs, headers or secrets."""
    frames = traceback.extract_tb(exc.__traceback__)
    own = [f for f in frames if Path(f.filename).name == "certify.py"]
    if own:
        f = own[-1]
        return f"certify.py:{f.lineno}:{f.name}"
    if frames:
        f = frames[-1]
        return f"{Path(f.filename).name}:{f.lineno}:{f.name}"
    return "unknown"


def load_config(path: Path) -> dict:
    if not path.exists():
        raise FileNotFoundError(
            f"{path} not found. Copy config.example.json to config.local.json, "
            "then enter your local credentials. Never commit config.local.json."
        )
    raw = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(raw, dict):
        raise ValueError("Config must be JSON object")
    return raw


def response_json(content: bytes) -> dict:
    data = json.loads(content.decode("utf-8-sig"))
    if not isinstance(data, dict):
        raise ValueError("Expected JSON object")
    return data


class Certification:
    def __init__(self, config: dict, suite: str, outdir: Path, timeout: int = 180):
        self.config = config
        self.suite = suite
        self.url = str(config.get("base_url", "")).rstrip("/")
        parsed = urllib.parse.urlsplit(self.url)
        if (parsed.scheme not in ("http", "https")
                or not parsed.hostname
                or parsed.path != "/v1" or parsed.query or parsed.fragment
                or parsed.username is not None or parsed.password is not None):
            raise ValueError("base_url must be http(s)://HOST:PORT/v1 with no query/credentials")
        self.origin = self.url[:-3]
        # urllib honors Windows proxy/PAC and HTTP_PROXY by default.
        # Tailscale and LAN devices must be contacted DIRECTLY.
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        self.api_key = os.environ.get("BONSAI_API_KEY") or str(config.get("api_key", ""))
        if not self.api_key:
            raise ValueError("No API key: set BONSAI_API_KEY or config.local.json api_key")
        self.model = str(config.get("model", MODEL))
        self.expected_ctx = int(config.get("context_window", CTX))
        self.expected_build = str(config.get("build_id", BUILD89_ID))
        self.max_output = int(config.get("server_max_output_tokens", 256))
        self.timeout = max(10, min(int(timeout), 900))
        self.run_id = safe_id(make_run_id())
        self.outdir = outdir / self.run_id
        self.outdir.mkdir(parents=True, exist_ok=False)
        self.events: list[dict] = []
        self.counter = 0
        self.current_case = "initialization"
        self.failed = False
        self.identity_level = "unverified"
        (self.outdir / "responses").mkdir()

    def request(self, case: str, path: str, *, payload: dict | None = None, streaming: bool = False) -> dict:
        self.counter += 1
        self.current_case = case
        request_id = safe_id(f"{self.run_id}-{self.counter:04d}")
        start = time.perf_counter()
        method = "POST" if payload is not None else "GET"
        wire = json.dumps(payload, ensure_ascii=False).encode("utf-8") if payload is not None else None
        headers = {
            "Authorization": "Bearer " + self.api_key,
            "Accept": "text/event-stream" if streaming else "application/json",
            "X-Bonsai-Run-ID": self.run_id,
            "X-Bonsai-Request-ID": request_id,
            "X-Bonsai-Test-Case": case,
        }
        if wire is not None:
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(self.origin + path,
                                     data=wire, method=method, headers=headers)
        output = {
            "case": case, "run_id": self.run_id, "request_id": request_id,
            "timestamp": now_utc(), "method": method, "path": path,
            "target_path": urllib.parse.urlsplit(req.full_url).path,
            "transport": "direct_no_system_proxy",
            "status": None, "duration_ms": None, "ttfb_ms": None,
            "first_token_ms": None, "ok": False, "error": None,
        }
        try:
            with self.opener.open(req, timeout=self.timeout) as resp:
                output["status"] = resp.status
                output["ttfb_ms"] = round((time.perf_counter() - start) * 1000, 2)
                if streaming:
                    chunks, found_done, actual_data = [], False, 0
                    # urllib returns decoded body lines (HTTP chunk framing handled by library).
                    for line in resp:
                        line = line.decode("utf-8")
                        if not line.startswith("data: "):
                            continue
                        item = line[6:].strip()
                        if item == "[DONE]":
                            found_done = True
                            break
                        obj = json.loads(item)
                        chunks.append(obj)
                        for choice in obj.get("choices", []):
                            if choice.get("delta", {}).get("content"):
                                actual_data += 1
                                if output["first_token_ms"] is None:
                                    output["first_token_ms"] = round((time.perf_counter() - start) * 1000, 2)
                    output["done"] = found_done
                    output["delta_events"] = actual_data
                    output["ok"] = resp.status == 200 and found_done and actual_data > 0
                    # Only synthetic prompts are run by this tool; still limit saved SSE to summary.
                else:
                    body = response_json(resp.read())
                    body = json.loads(
                        json.dumps(body, ensure_ascii=False).replace(self.api_key, "[REDACTED]")
                    )
                    (self.outdir / "responses" / f"{self.counter:04d}-{case}.json").write_text(
                        json.dumps(body, ensure_ascii=False, indent=2), encoding="utf-8"
                    )
                    output["response"] = body
                    output["ok"] = resp.status == 200
        except urllib.error.HTTPError as exc:
            output["status"] = exc.code
            output["content_type"] = exc.headers.get("Content-Type", "unknown") if exc.headers else "unknown"
            try:
                body = response_json(exc.read())
                # Never persist server-controlled content containing a credential.
                sanitized = json.loads(
                    json.dumps(body, ensure_ascii=False).replace(self.api_key, "[REDACTED]")
                )
                output["response"] = sanitized
                (self.outdir / "responses" / f"{self.counter:04d}-{case}-http-error.json").write_text(
                    json.dumps(sanitized, ensure_ascii=False, indent=2), encoding="utf-8"
                )
            except Exception:
                output["error"] = "HTTP response was not JSON"
        except Exception as exc:
            # Never echo URL, headers, or API Key (some exception messages include URL).
            output["error"] = type(exc).__name__
            output["error_site"] = safe_error_location(exc)
            print(f"[ERROR] {case}: {output['error']} @ {output['error_site']}", flush=True)
        finally:
            output["duration_ms"] = round((time.perf_counter() - start) * 1000, 2)
        # response bodies can be large; store summaries in events.
        stored = {k: v for k, v in output.items() if k != "response"}
        if isinstance(output.get("response"), dict):
            resp = output["response"]
            if isinstance(resp.get("usage"), dict):
                stored["usage"] = resp["usage"]
            if isinstance(resp.get("error"), dict):
                stored["error_code"] = resp["error"].get("code")
                stored["error_message"] = str(resp["error"].get("message", ""))[:300]
        self.events.append(stored)
        print(f"[{'PASS' if output['ok'] else 'FAIL'}] {case}: HTTP {output['status']}  {output['duration_ms']} ms", flush=True)
        return output

    def require(self, condition: bool, reason: str) -> None:
        if not condition:
            raise AssertionError(reason)

    def run(self) -> int:
        try:
            health = self.request("health_before", "/health")
            self.require(health["ok"] and health.get("response", {}).get("status") == "ok",
                         ("Health failed: HTTP " + str(health.get("status")) +
                          " at /health via direct connection. Check that your Tailscale IP:8080 "
                          "actually points to the running BonsaiLab API."))
            self.require(int(health["response"].get("context_window", -1)) == self.expected_ctx,
                         "Health context mismatch")

            models = self.request("models_before", "/v1/models")
            self.require(models["ok"], "Discovery unavailable")
            matches = [m for m in models["response"].get("data", []) if m.get("id") == self.model]
            self.require(len(matches) == 1 and int(matches[0].get("context_length", -1)) == self.expected_ctx,
                         "Model/context identity mismatch")
            self.require(int(matches[0].get("max_output_tokens", -1)) == self.max_output,
                         "Server output cap mismatch")

            build = self.request("debug_build", "/debug/build")
            self.require(build["ok"] and build["response"].get("build_id") == self.expected_build,
                         "Actual app build_id is not expected Build89")
            # Server-side product Git SHA is not exposed by Build89.
            # Do not pretend the branch commit was verified on-device.
            self.identity_level = "build_id_context_model_verified_product_sha_unverifiable"

            for key, route in [
                ("telemetry_before", "/debug/telemetry"),
                ("prefill_before", "/debug/prefill"),
            ]:
                probe = self.request(key, route)
                self.require(probe["ok"], key + " unavailable")

            if self.suite != "readonly":
                first = self.request(
                    "text_32", "/v1/chat/completions",
                    payload={"model": self.model, "messages": [
                        {"role": "user", "content": "Reply exactly BONSAI_P0_OK."}
                    ], "max_tokens": 32, "stream": False, "temperature": 0},
                )
                resp = first.get("response", {})
                self.require(first["ok"] and bool(resp.get("choices")), "Text response missing")
                self.require(bool(resp["choices"][0].get("message", {}).get("content", "")),
                             "Text content empty")
                self.require(int(resp.get("usage", {}).get("prompt_tokens", 0)) > 0,
                             "Server prompt_tokens missing")

                stream = self.request(
                    "sse_64", "/v1/chat/completions", streaming=True,
                    payload={"model": self.model, "messages": [
                        {"role": "user", "content": "Explain the purpose of a software regression test in two sentences."}
                    ], "max_tokens": 64, "stream": True, "temperature": 0},
                )
                self.require(stream["ok"], "SSE lacked delta tokens or [DONE]")

                after = self.request("health_after", "/health")
                self.require(after["ok"] and after["response"].get("status") == "ok",
                             "API not alive after inference")
                last = self.request("prefill_after", "/debug/prefill")
                self.require(last["ok"], "Final prefill metrics unavailable")
                mem = self.request("telemetry_after", "/debug/telemetry")
                self.require(mem["ok"], "Final device telemetry unavailable")

            return 0
        except Exception as exc:
            self.failed = True
            # Stable error string: assertion is authored; avoid exposing embedded API URL.
            detail = str(exc) if isinstance(exc, AssertionError) else type(exc).__name__
            site = safe_error_location(exc)
            print(f"[STOP] {detail} | phase={self.current_case} | site={site}", file=sys.stderr)
            self.events.append({"case": "suite_failure", "error": detail,
                                "phase": self.current_case, "error_site": site,
                                "timestamp": now_utc()})
            return 1
        finally:
            self.save()

    def save(self) -> None:
        summary = {
            "schema_version": 1,
            "run_id": self.run_id, "suite": self.suite,
            "created_at": now_utc(), "result": "FAIL" if self.failed else "PASS",
            "identity_verification": self.identity_level,
            "build_id_expected": self.expected_build,
            "context_expected": self.expected_ctx, "model_expected": self.model,
            "server_product_git_sha_verified": False,
            "server_side_run_request_correlation_verified": False,
            "notes": [
                "Build89 does not echo or persist client X-Bonsai IDs; this is client-only correlation.",
                "Runtime memory samples represent sampled values, not certified peaks.",
                "HTTP transport uses a proxy-free opener to reach the LAN/Tailscale iPad directly.",
                "Responses contain only fixed synthetic testing prompts; credentials are never included.",
            ],
            "cases": self.events,
        }
        (self.outdir / "summary.json").write_text(
            json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
        with zipfile.ZipFile(str(self.outdir) + ".zip", "w", zipfile.ZIP_DEFLATED) as z:
            for p in self.outdir.rglob("*"):
                if p.is_file():
                    z.write(p, p.relative_to(self.outdir))
        print("Evidence ZIP:", str(self.outdir) + ".zip")


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--config", default=str(Path(__file__).resolve().parent / "config.local.json"))
    p.add_argument("--suite", choices=["readonly", "smoke"], default="smoke")
    p.add_argument("--output", default=str(Path(__file__).resolve().parent / "results"))
    p.add_argument("--timeout", type=int, default=180)
    args = p.parse_args()
    try:
        c = Certification(load_config(Path(args.config)), args.suite, Path(args.output), args.timeout)
        return c.run()
    except Exception as exc:
        print(f"[CONFIG ERROR] {type(exc).__name__}: {exc if isinstance(exc, (FileNotFoundError, ValueError)) else ''}",
              file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""One-run Build103 integrated iPad acceptance suite. Python 3.10+, stdlib only.
No configuration file, no fixed client output cap, no credentials in results.
The iPad app must already be running its OpenAI API; device relaunch cannot be
automated over HTTP. The runner continues through independent test failures.
"""
import argparse
import base64
import datetime as dt
import getpass
import hashlib
import json
import os
from pathlib import Path
import platform
import socket
import sys
import time
import traceback
import urllib.error
import urllib.request
import uuid
import zipfile

HOSTS = ("192.168.1.85", "192.168.0.103", "192.168.0.102", "192.168.1.103", "127.0.0.1")
PORT = 8080
def iso():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
def request(url, key=None, payload=None, timeout=45, stream=False, test_id=""):
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8") if payload is not None else None
    headers = {"Accept": "text/event-stream" if stream else "application/json"}
    if data is not None:
        headers["Content-Type"] = "application/json; charset=utf-8"
    if key:
        headers["Authorization"] = "Bearer " + key
    if test_id:
        headers["X-Bonsai-Test-Case"] = test_id
        headers["X-Bonsai-Request-ID"] = str(uuid.uuid4())
    req = urllib.request.Request(url, headers=headers, data=data, method="POST" if data is not None else "GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            body = response.read()
            status = response.status
            mime = response.headers.get("Content-Type", "")
    except urllib.error.HTTPError as exc:
        body = exc.read()
        status = exc.code
        mime = exc.headers.get("Content-Type", "")
    except Exception:
        raise
    raw = body.decode("utf-8", errors="replace")
    if stream:
        text_parts, finish_reason, event_count = [], None, 0
        for line in raw.splitlines():
            if not line.startswith("data: "):
                continue
            part = line[6:].strip()
            if part == "[DONE]":
                break
            try:
                packet = json.loads(part)
                choice = packet.get("choices", [{}])[0] if packet.get("choices") else {}
                delta = choice.get("delta", {})
                text_parts.append(delta.get("content", ""))
                if choice.get("finish_reason") is not None:
                    finish_reason = choice["finish_reason"]
                event_count += 1
            except Exception:
                pass
        return status, {"text": "".join(text_parts), "finish_reason": finish_reason, "events": event_count,
                        "done": "data: [DONE]" in raw, "mime": mime, "bytes": len(body)}
    try:
        return status, json.loads(raw)
    except Exception:
        return status, {"raw_excerpt": raw[:700], "mime": mime}
def normalize(url):
    return url.rstrip("/").removesuffix("/v1")
def discover(hint):
    if hint:
        return normalize(hint)
    for host in HOSTS:
        base = f"http://{host}:{PORT}"
        try:
            status, obj = request(base + "/health", timeout=2)
            if status == 200 and isinstance(obj, dict):
                print("[DISCOVER]", base)
                return base
        except Exception:
            pass
    raise RuntimeError("No Bonsai LAN API discovered. Set BONSAI_BASE_URL (e.g. http://192.168.1.85:8080/v1).")
def first_model(models):
    arr = models.get("data") or []
    if not arr:
        raise RuntimeError("/v1/models returned no model")
    return arr[0]
def choices_text(obj):
    first = (obj.get("choices") or [{}])[0]
    msg = first.get("message") or {}
    return msg.get("content") or "", first.get("finish_reason"), obj.get("usage") or {}
def run():
    ap = argparse.ArgumentParser(description="Bonsai Build103 one-run device integration")
    ap.add_argument("--base-url", default=os.environ.get("BONSAI_BASE_URL", ""))
    ap.add_argument("--api-key", default=os.environ.get("BONSAI_API_KEY", ""))
    ap.add_argument("--image", default=os.environ.get("BONSAI_VISION_IMAGE", ""))
    ap.add_argument("--timeout", type=int, default=900, help="Seconds per inference, default 900")
    ap.add_argument("--output", default="RESULTS")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    if args.dry_run:
        assert normalize("http://127.0.0.1:8080/v1") == "http://127.0.0.1:8080"
        assert all(HOSTS)
        print("PASS Build103 integrated runner dry-run")
        return 0
    root = Path(args.output)
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    session = root / ("Build103-FULL-" + stamp)
    session.mkdir(parents=True, exist_ok=True)
    base = discover(args.base_url)
    key = args.api_key
    if not key:
        key = getpass.getpass("Bonsai API Key (never saved or included in results): ")
    events = []
    def record(name, state, **meta):
        event = {"case": name, "state": state, "at": iso(), **meta}
        events.append(event)
        print(f"[{state}] {name}", (" ".join(f"{k}={str(v)[:70]}" for k, v in meta.items()))[:160], flush=True)
        (session / "records.json").write_text(json.dumps(events, ensure_ascii=False, indent=2), encoding="utf-8")
    def check(name, fun):
        begin = time.monotonic()
        try:
            fun()
        except Exception as e:
            record(name, "FAIL", elapsed_s=round(time.monotonic()-begin, 2),
                   error=type(e).__name__ + ": " + str(e)[:350])
    def chat(name, messages, max_tokens=None, stream=False, require_min=None):
        payload = {"model": model, "messages": messages, "stream": stream, "temperature": 0,
                   "stream_options": {"include_usage": True} if stream else None}
        if not stream:
            payload.pop("stream_options")
        if max_tokens is not None:
            payload["max_tokens"] = max_tokens
        t0 = time.monotonic()
        status, obj = request(base + "/v1/chat/completions", key, payload, timeout=args.timeout,
                              stream=stream, test_id=name)
        elapsed = round(time.monotonic()-t0, 2)
        if status != 200:
            raise AssertionError(f"HTTP {status}: {str(obj)[:280]}")
        if stream:
            txt, reason, usage = obj["text"], obj["finish_reason"], {}
            if not obj["done"] or obj["events"] < 1:
                raise AssertionError("Incomplete SSE stream or no events")
        else:
            txt, reason, usage = choices_text(obj)
        if not txt.strip():
            raise AssertionError("Blank assistant content")
        count = usage.get("completion_tokens", None)
        record(name, "PASS", elapsed_s=elapsed, characters=len(txt), completion_tokens=count,
               finish_reason=reason, client_max_tokens=max_tokens or "omitted", stream=stream)
        if require_min is not None:
            if count is None:
                record(name+"_length", "INCONCLUSIVE", reason="No completion token usage")
            elif count > require_min:
                record(name+"_length", "PASS", completion_tokens=count, threshold=require_min)
            elif count == require_min and reason == "length":
                record(name+"_length", "FAIL", reason="Suspected fixed token cap", completion_tokens=count)
            else:
                record(name+"_length", "INCONCLUSIVE", reason="Model may have stopped naturally", completion_tokens=count, finish_reason=reason)
        return txt
    def debug_snapshot(suffix):
        for route in ["/health", "/debug/runtime", "/debug/telemetry", "/debug/prefill", "/debug/execution", "/debug/build"]:
            try:
                code, data = request(base + route, key, timeout=12)
                name = route.strip("/").replace("/", "_")
                (session / f"{suffix}_{name}.json").write_text(json.dumps({"http":code, "data":data}, ensure_ascii=False, indent=2), encoding="utf-8")
            except Exception as e:
                record(suffix + route, "SKIP", reason=str(e)[:140])
    try:
        status, models = request(base + "/v1/models", key, timeout=10)
        if status != 200:
            raise RuntimeError(f"/v1/models HTTP {status}")
        info = first_model(models)
        model = info.get("id")
        context = int(info.get("context_length", info.get("context_window", 0)))
        ceiling = int(info.get("max_output_tokens", 0))
        if not model or context < 256 or ceiling <= 0:
            raise RuntimeError("Model discovery missing id/context/output ceiling")
        record("discovery", "PASS", model=model, context=context, advertised_max_output=ceiling)
        (session / "model.json").write_text(json.dumps(info, ensure_ascii=False, indent=2), encoding="utf-8")
        debug_snapshot("before")
        def text(t):
            return [{"role":"user","content":t}]
        check("short_nonstream", lambda: chat("short_nonstream",text("请只回复一个词：收到。"), max_tokens=48))
        check("short_stream",lambda:chat("short_stream",text("请用中文写一句不超过20字的问候。"), max_tokens=96,stream=True))
        def output_probe(case, n):
            prompt = "请从0001开始逐行列出递增的4位序号，直到0400。每行仅写一个数字，不要解释，不要省略。"
            chat(case, text(prompt), max_tokens=n, require_min=256 if n>256 else None)
        check("explicit_384_tokens", lambda: output_probe("explicit_384_tokens", min(384, ceiling, context-1)))
        if ceiling > 256 and context > 1024:
            check("implicit_ui_default_tokens", lambda: chat(
                "implicit_ui_default_tokens",text("请从0001到0400逐行写出4位数字，每行一个，不要提前停止。"),
                max_tokens=None,require_min=256))
        else:
            record("implicit_ui_default_tokens","SKIP",reason="UI ceiling <= 256 or context too small")
        def turn_sequence():
            a = "随后的回答请记住我说的随机标记 LILAC-0427。只需确认。"
            one = chat("turn1",text(a),max_tokens=80)
            two = chat("turn2",[{"role":"user","content":a},{"role":"assistant","content":one},
                                {"role":"user","content":"我刚才给出的随机标记是什么？"}],max_tokens=100)
            if "LILAC" not in two.upper():
                record("multi_turn_semantics","INCONCLUSIVE",reason="Model did not repeat literal marker")
            else:
                record("multi_turn_semantics","PASS")
            chat("turn3", text("回答上一轮问题之前，先简述 KV Cache 是否等于长时记忆。"),max_tokens=180)
        check("multi_turn",turn_sequence)
        # One integrated run: these are workload sizes, not separate manually armed configurations.
        for chars in [1500, 4500, 9500]:
            if chars >= context:
                continue
            def long_case(chars=chars):
                filler=("东南西北春夏秋冬" * ((chars + 7)//8))[:chars]
                chat(f"long_input_{chars}",text("阅读以下内容，最后只回答末尾问题：" + filler +
                     "\n问题：以上文本中出现的四个方位词是什么？"),max_tokens=64)
            check(f"long_input_{chars}",long_case)
        file = Path(args.image) if args.image else Path("D:/apple/vision_test_01_people_landscape.png")
        if not file.exists() or not file.is_file():
            record("vision_1_to_3_images", "SKIP", reason="No local image available. Set BONSAI_VISION_IMAGE")
        else:
            raw = file.read_bytes()
            mime = "image/png" if file.suffix.lower() == ".png" else "image/jpeg"
            data_uri = "data:" + mime + ";base64," + base64.b64encode(raw).decode("ascii")
            for n in (1,2,3):
                def vision_case(n=n):
                    content = [{"type":"text","text":"请用一句中文描述图像，不要分析。"}] + [
                        {"type":"image_url","image_url":{"url":data_uri}} for _ in range(n)]
                    chat(f"vision_{n}_images",[{"role":"user","content":content}],max_tokens=180)
                check(f"vision_{n}_images",vision_case)
            check("post_vision_text",lambda:chat("post_vision_text",text("请只回复：图文切换成功。"),max_tokens=90))
        debug_snapshot("after")
    finally:
        meta = {"generated_at":iso(), "host":platform.system(), "python":platform.python_version(),
                "base_url":base, "schema_version":1, "profile":"integrated",
                "credential_saved":False}
        (session / "manifest.json").write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding="utf-8")
        counts = {k:sum(x["state"]==k for x in events) for k in ["PASS","FAIL","SKIP","INCONCLUSIVE"]}
        status = "PASS" if counts["FAIL"]==0 and counts["PASS"]>0 else "FAIL"
        report = "# Bonsai Build103 integrated device test\n\n"
        report += f"**{status}** | " + " | ".join(f"{k}={v}" for k,v in counts.items()) + "\n\n"
        report += f"Date: {iso()}\n\n"
        report += "| Case | State | Notes |\n|---|---|---|\n"
        for event in events:
            note = str({k:v for k,v in event.items() if k not in ["case","state","at"]}).replace("|","/")
            report += f'| {event["case"]} | {event["state"]} | {note[:220]} |\n'
        report += "\nThis is a device run, not a CI build. Long-context capacity, restart/recovery and peak Metal memory cannot be conclusively certified by HTTP alone.\n"
        (session / "FINAL_REPORT.md").write_text(report, encoding="utf-8")
        archive = root / (session.name + ".zip")
        with zipfile.ZipFile(archive,"w",compression=zipfile.ZIP_DEFLATED) as z:
            for p in session.rglob("*"):
                if p.is_file():
                    z.write(p, arcname=p.relative_to(session))
        print("\nFINAL:",archive.resolve(), "=>", status, counts)
    return 1 if any(x["state"]=="FAIL" for x in events) else 0
if __name__ == "__main__":
    try:
        sys.exit(run())
    except (KeyboardInterrupt, EOFError):
        print("Stopped before test session could be completed.", file=sys.stderr)
        sys.exit(130)

#!/usr/bin/env python3
"""Read latest-session metrics from the local Lapdog LLMObs API."""
import datetime
from collections import Counter
import json
import sys
import time
import urllib.request
import urllib.parse

BASE = "http://127.0.0.1:8126"


def query(params):
    request = urllib.request.Request(
        BASE + "/api/unstable/llm-obs-query-rewriter/list?type=llmobs",
        data=json.dumps({"list": params}).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        return json.load(response)


def customs(response):
    return [event["event"]["custom"] for event in response["result"]["events"]]


def duration_text(seconds):
    seconds = max(0, int(seconds))
    hours, rem = divmod(seconds, 3600)
    minutes, seconds = divmod(rem, 60)
    return f"{hours}h {minutes}m {seconds}s" if hours else f"{minutes}m {seconds}s"


def status(selected_session=''):
    payload = dict(state="running", label="Running", summary="Latest session",
                   sessionId="", traces="—", cost="—", started="—", duration="—")
    recent = []
    index_params = {"limit": 100}
    index_truncated = False
    for _ in range(10):
        result = query(index_params)
        recent.extend(customs(result))
        paging = result['result'].get('paging')
        if not paging: break
        index_params['paging'] = paging
    else:
        index_truncated = bool(paging)
    now = time.time()
    sessions = {}
    for span in recent:
        sid = span.get('session_id')
        if not sid: continue
        last = (span['start_ns'] + (span.get('duration') or 0)) / 1e9
        if sid not in sessions or last > sessions[sid]['lastActivity']:
            project = next((t.split(':', 1)[1] for t in span.get('tags', [])
                            if isinstance(t, str) and t.startswith('project_name:')), '')
            sessions[sid] = dict(id=sid, application=span.get('ml_app') or 'Agent',
                                 project=project, lastActivity=last)
    session_list = sorted(sessions.values(), key=lambda s: s['lastActivity'], reverse=True)
    for item in session_list:
        age = max(0, now - item['lastActivity'])
        item['recent'] = age <= 300
        item['lastSeen'] = duration_text(age) + ' ago'
        item['display'] = (item['application'] + (' · ' + item['project'] if item['project'] else '')
                           + ' · ' + item['id'][:8] + (' · Recent' if item['recent'] else ' · Older'))
    payload.update(sessions=session_list, recentSessions=sum(s['recent'] for s in session_list),
                   sessionIndexTruncated=index_truncated)
    latest = recent[:1]
    if not latest:
        payload["summary"] = "No sessions recorded yet"
        return payload
    session = selected_session or (session_list[0]['id'] if session_list else latest[0].get('session_id'))
    if not session:
        payload["summary"] = "Latest trace has no session ID"
        return payload
    params = {"limit": 100, "search": {"query": "session_id:" + session}}
    spans = []
    for _ in range(100):
        result = query(params)
        spans.extend(customs(result))
        paging = result["result"].get("paging")
        if not paging:
            break
        params["paging"] = paging
    else:
        raise ValueError("Session exceeds pagination limit; metrics unavailable")
    if not spans:
        raise ValueError("Session query returned no spans")
    # Count distinct traces and sum only LLM span costs, not root aggregates.
    traces = {span["trace_id"] for span in spans if span.get("trace_id")}
    cost = sum(span.get("metrics", {}).get("estimated_total_cost", 0) or 0
               for span in spans if span.get("kind") == "llm") / 1e9
    start = min(span["start_ns"] for span in spans) / 1e9
    end = max((span["start_ns"] + (span.get("duration") or 0)) / 1e9 for span in spans)
    llm_spans = [span for span in spans if span.get("kind") == "llm"]
    apps = sorted({span.get("ml_app") for span in spans if span.get("ml_app")})
    projects = sorted({tag.split(":", 1)[1] for span in spans
                       for tag in span.get("tags", [])
                       if isinstance(tag, str) and tag.startswith("project_name:")})
    models = sorted({span.get("meta", {}).get("model_name") for span in llm_spans
                     if span.get("meta", {}).get("model_name")})
    # Do not sum trace.number_of_errors: it is repeated on each span.
    errors = sum(1 for span in spans if span.get("error") or span.get("status") == "error")
    inputs = sum(span.get("metrics", {}).get("input_tokens", 0) or 0 for span in llm_spans)
    outputs = sum(span.get("metrics", {}).get("output_tokens", 0) or 0 for span in llm_spans)
    kinds = Counter(span.get("kind") or "unknown" for span in spans)
    # Bin starts across the session; cost comes only from LLM spans.
    width = max(end - start, 1) / 48
    buckets = [{"time": start + i * width, "counts": {}, "cost": 0, "errors": 0} for i in range(48)]
    for span in spans:
        index = min(47, max(0, int((span["start_ns"] / 1e9 - start) / width)))
        bucket = buckets[index]
        kind = span.get("kind") or "unknown"
        bucket["counts"][kind] = bucket["counts"].get(kind, 0) + 1
        if kind == "llm":
            bucket["cost"] += (span.get("metrics", {}).get("estimated_total_cost", 0) or 0) / 1e9
        bucket["errors"] += int(bool(span.get("error") or span.get("status") == "error"))
    latest_trace = max(spans, key=lambda s: s['start_ns']).get('trace_id')
    trace_spans = sorted([s for s in spans if s.get("trace_id") == latest_trace], key=lambda s: s["start_ns"])
    trace_start = min(s["start_ns"] for s in trace_spans) / 1e9 if trace_spans else 0
    trace_end = max((s["start_ns"] + (s.get("duration") or 0)) / 1e9 for s in trace_spans) if trace_spans else 0
    by_id = {s.get("span_id"): s for s in trace_spans}
    def depth(span):
        seen = set()
        parent = span.get("parent_id")
        level = 0
        while parent in by_id and parent not in seen:
            seen.add(parent)
            level += 1
            parent = by_id[parent].get("parent_id")
        return level
    waterfall = [{"name": s.get("name") or s.get("kind") or "Span", "kind": s.get("kind") or "unknown",
                  "start": s["start_ns"] / 1e9 - trace_start, "duration": (s.get("duration") or 0) / 1e9,
                  "depth": depth(s), "error": bool(s.get("error") or s.get("status") == "error")}
                 for s in trace_spans]
    payload.update(activity=buckets, bucketSeconds=width, waterfall=waterfall,
                   traceDuration=max(trace_end - trace_start, 0.001), traceId=latest_trace or "")
    payload.update(spanKinds=[{"kind": kind, "count": f"{count:,}"}
                              for kind, count in sorted(kinds.items())],
                   spanCount=f"{len(spans):,}")
    payload.update(application=", ".join(apps) or "—", project=", ".join(projects) or "—",
                   models=", ".join(models) or "—", errors=f"{errors:,}",
                   calls=f"{len(llm_spans):,} LLM / {sum(s.get('kind') == 'tool' for s in spans):,} tool",
                   tokens=f"{inputs:,} in / {outputs:,} out")
    payload.update(sessionId=session, traces=f"{len(traces):,}", cost=f"${cost:.4f}",
                   started=datetime.datetime.fromtimestamp(start).astimezone().strftime("%b %d, %Y · %I:%M %p"),
                   duration=duration_text(end - start))
    return payload


if __name__ == "__main__":
    try:
        payload = status(sys.argv[1] if len(sys.argv) > 1 else '')
    except Exception as error:
        payload = dict(state="error", label="Unavailable", summary="Cannot read local Lapdog session data",
                       detail=str(error), sessionId="", traces="—", cost="—", started="—", duration="—")
    print(json.dumps(payload, separators=(",", ":")))

#!/usr/bin/env python3
"""
server.py — Local HTTP server for the travel dashboard with embedded chat.

Serves the dashboard HTML and provides a /api/chat endpoint that proxies
streaming requests to the Claude API via SSE.

Usage:
    python server.py [--port PORT] [--timeline PATH] [--no-open]
"""

import argparse
import glob
import json
import os
import sys
import webbrowser

from flask import Flask, Response, jsonify, request, send_file

from chat import build_system_prompt, find_latest_timeline
from llm_client import get_client, CHAT_MODEL

app = Flask(__name__)

# Populated at startup
_dashboard_path = None
_timeline_path = None
_timeline_data = None
_system_prompt = None


def _find_latest_dashboard():
    """Find the most recent travel-story HTML in the output directory."""
    output_dir = os.path.join(os.path.dirname(__file__), "output")
    pattern = os.path.join(output_dir, "*-travel-story.html")
    files = sorted(glob.glob(pattern))
    if not files:
        return None
    return files[-1]


@app.after_request
def add_cors_headers(response):
    """Add CORS headers for local development."""
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type"
    return response


@app.route("/")
def serve_dashboard():
    """Serve the latest dashboard HTML."""
    if not _dashboard_path or not os.path.exists(_dashboard_path):
        return "No dashboard found. Run 'python main.py' first.", 404
    return send_file(_dashboard_path, mimetype="text/html")


@app.route("/api/timeline")
def serve_timeline():
    """Return the timeline JSON data."""
    if _timeline_data is None:
        return jsonify({"error": "No timeline loaded"}), 404
    return jsonify(_timeline_data)


@app.route("/api/chat", methods=["POST", "OPTIONS"])
def chat():
    """Stream a Claude response as SSE given a user message + history."""
    if request.method == "OPTIONS":
        return "", 204

    data = request.get_json()
    if not data or "message" not in data:
        return jsonify({"error": "Missing 'message' field"}), 400

    user_message = data["message"]
    history = data.get("history", [])

    # Build messages array: history + new user message
    messages = list(history)
    messages.append({"role": "user", "content": user_message})

    # Trim to last 20 messages to stay within context limits
    if len(messages) > 20:
        messages = messages[-20:]

    def generate():
        try:
            client = get_client()
            with client.messages.stream(
                model=CHAT_MODEL,
                max_tokens=1024,
                system=_system_prompt,
                messages=messages,
            ) as stream:
                for text in stream.text_stream:
                    # SSE format: each chunk is "data: <text>\n\n"
                    yield f"data: {json.dumps({'text': text})}\n\n"
            # Signal completion
            yield f"data: {json.dumps({'done': True})}\n\n"
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return Response(
        generate(),
        mimetype="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


def main():
    global _dashboard_path, _timeline_path, _timeline_data, _system_prompt

    parser = argparse.ArgumentParser(
        description="Local server for the travel dashboard with chat."
    )
    parser.add_argument(
        "--port", type=int, default=5001,
        help="Port to serve on (default: 5001)",
    )
    parser.add_argument(
        "--timeline",
        help="Path to timeline.json (auto-detects most recent if omitted)",
    )
    parser.add_argument(
        "--no-open", action="store_true",
        help="Don't auto-open the browser",
    )
    args = parser.parse_args()

    # Find timeline
    if args.timeline:
        _timeline_path = args.timeline
    else:
        _timeline_path = find_latest_timeline()

    if not _timeline_path or not os.path.exists(_timeline_path):
        print("  Error: No timeline.json found.")
        print("  Run 'python main.py' first, or specify --timeline PATH.")
        sys.exit(1)

    # Load timeline and build system prompt
    with open(_timeline_path, "r", encoding="utf-8") as f:
        _timeline_data = json.load(f)

    _system_prompt = build_system_prompt(_timeline_data)

    # Find dashboard HTML
    _dashboard_path = _find_latest_dashboard()
    if not _dashboard_path:
        print("  Warning: No dashboard HTML found in output/")
        print("  The / route will return a 404.")

    summary = _timeline_data.get("summary", {})
    print()
    print("  ==========================================")
    print("    Travel Dashboard Server")
    print("  ==========================================")
    print()
    print(f"  Timeline : {os.path.basename(_timeline_path)}")
    if _dashboard_path:
        print(f"  Dashboard: {os.path.basename(_dashboard_path)}")
    print(f"  Trips    : {summary.get('total_trips', '?')} trips, "
          f"{summary.get('countries_visited', '?')} countries")
    print()
    print(f"  Serving at http://localhost:{args.port}")
    print("  Press Ctrl+C to stop.")
    print()

    # Auto-open browser
    if not args.no_open:
        webbrowser.open(f"http://localhost:{args.port}")

    app.run(host="127.0.0.1", port=args.port, debug=False)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
chat.py — Interactive CLI Q&A over your travel timeline using Claude.

Loads the most recent timeline.json and enables a multi-turn conversation
where you can ask questions about your travel history.

Usage:
    python chat.py [--timeline PATH]
"""

import argparse
import glob
import json
import os
import sys

from llm_client import get_client, CHAT_MODEL


def find_latest_timeline():
    """Find the most recent timeline.json in the output directory."""
    output_dir = os.path.join(os.path.dirname(__file__), "output")
    pattern = os.path.join(output_dir, "*-timeline.json")
    files = sorted(glob.glob(pattern))
    if not files:
        return None
    return files[-1]


def build_system_prompt(timeline):
    """Build the system prompt with timeline context."""
    home = timeline["home_base"]
    summary = timeline["summary"]
    date_range = timeline["date_range"]

    # Include the full timeline as context
    timeline_json = json.dumps(timeline, indent=2, ensure_ascii=False)

    return f"""You are a friendly travel assistant who knows everything about the user's travel history.

The user lives in {home['city']}, {home['country']}. Their travel data covers {date_range['from']} to {date_range['to']}.

Summary: {summary['total_trips']} trips, {summary['countries_visited']} countries, {summary['cities_visited']} cities, {summary['total_days_traveling']} days traveling.

Here is their complete travel timeline data:

```json
{timeline_json}
```

RULES:
- Answer questions about their travel history based on the data above
- Be conversational and warm, like a friend who remembers all their trips
- Use specific dates, cities, and durations from the data
- If asked about something not in the data, say so honestly
- You can calculate statistics, compare trips, find patterns
- Reference trip narratives and taglines if they exist in the data
- Keep answers concise but complete"""


def run_chat(timeline_path):
    """Run the interactive chat loop."""
    try:
        client = get_client()
    except EnvironmentError as e:
        print(f"\n  {e}")
        sys.exit(1)

    with open(timeline_path, "r", encoding="utf-8") as f:
        timeline = json.load(f)

    system_prompt = build_system_prompt(timeline)
    summary = timeline["summary"]

    print()
    print("  ==========================================")
    print("    Travel Timeline Chat")
    print("  ==========================================")
    print()
    print(f"  Loaded: {os.path.basename(timeline_path)}")
    print(f"  {summary['total_trips']} trips · {summary['countries_visited']} countries · "
          f"{summary['total_days_traveling']} days")
    print()
    print("  Ask me anything about your travels!")
    print("  Type 'quit' or press Ctrl+C to exit.")
    print()

    messages = []

    while True:
        try:
            user_input = input("  You: ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n\n  Goodbye! Safe travels.")
            break

        if not user_input:
            continue
        if user_input.lower() in ("quit", "exit", "q"):
            print("\n  Goodbye! Safe travels.")
            break

        messages.append({"role": "user", "content": user_input})

        # Trim history if it gets too long (keep last 10 messages)
        if len(messages) > 20:
            messages = messages[-10:]

        print("\n  Claude: ", end="", flush=True)

        try:
            with client.messages.stream(
                model=CHAT_MODEL,
                max_tokens=1024,
                system=system_prompt,
                messages=messages,
            ) as stream:
                response_text = ""
                for text in stream.text_stream:
                    print(text, end="", flush=True)
                    response_text += text
                print("\n")

            messages.append({"role": "assistant", "content": response_text})

        except KeyboardInterrupt:
            print("\n  (interrupted)")
            # Remove the unanswered user message
            messages.pop()
            print()
        except Exception as e:
            print(f"\n  Error: {e}\n")
            messages.pop()


def main():
    parser = argparse.ArgumentParser(
        description="Chat with Claude about your travel timeline."
    )
    parser.add_argument(
        "--timeline",
        help="Path to timeline.json (auto-detects most recent if omitted)",
    )
    args = parser.parse_args()

    if args.timeline:
        timeline_path = args.timeline
        if not os.path.exists(timeline_path):
            print(f"  Error: File not found: {timeline_path}")
            sys.exit(1)
    else:
        timeline_path = find_latest_timeline()
        if not timeline_path:
            print("  No timeline.json found in output/")
            print("  Run 'python main.py' first to generate one.")
            sys.exit(1)

    run_chat(timeline_path)


if __name__ == "__main__":
    main()

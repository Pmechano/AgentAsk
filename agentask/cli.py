"""CLI presentation, kept separate from storage and GUI code."""

import argparse
import json
from pathlib import Path
import sys

from .service import start_question, wait_for_response


def main(argv=None):
    parser = argparse.ArgumentParser(description="Ask the user in an independent Windows window.")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--question", "-q", help="Question text")
    source.add_argument("--question-file", type=Path, help="Read question from a UTF-8 file")
    parser.add_argument("--agent", default="unknown", help="Agent name displayed in the window")
    parser.add_argument("--title", default="AgentAsk", help="Window title")
    parser.add_argument("--detach", action="store_true", help="Return file locations immediately")
    args = parser.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    try:
        question = (args.question_file.read_text(encoding="utf-8-sig")
                    if args.question_file else args.question)
        metadata, process = start_question(question, agent=args.agent, title=args.title)
        if args.detach:
            print(json.dumps(metadata, ensure_ascii=False), flush=True)
            return 0
        print(json.dumps(metadata, ensure_ascii=False), file=sys.stderr, flush=True)
        response = wait_for_response(metadata, process)
        print(json.dumps(response, ensure_ascii=False), flush=True)
        return {"answered": 0, "cancelled": 2, "error": 1}[response["status"]]
    except KeyboardInterrupt:
        print("Caller interrupted; an open window may still save its response.", file=sys.stderr)
        return 130
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        return 1

"""Request storage and Windows UI process lifecycle; no third-party dependencies."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import uuid
from datetime import datetime, timezone


ROOT = Path(__file__).resolve().parent.parent


def _now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _write_json(path, value):
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    os.replace(str(temporary), str(path))


def _windows_path(path):
    if os.name == "nt":
        return str(path.resolve())
    return subprocess.check_output(
        ["wslpath", "-w", str(path.resolve())], encoding="utf-8"
    ).strip()


def _powershell():
    executable = shutil.which("powershell.exe")
    if executable:
        return executable
    if os.name == "nt":
        candidate = Path(os.environ.get("SystemRoot", r"C:\Windows")) / (
            "System32/WindowsPowerShell/v1.0/powershell.exe"
        )
        if candidate.is_file():
            return str(candidate)
    raise RuntimeError("Windows PowerShell was not found. Run on Windows or WSL with Windows interop enabled.")


def _launch(request_path, log_path):
    command = [
        _powershell(), "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass",
        "-WindowStyle", "Hidden", "-File", _windows_path(ROOT / "ui" / "ask-window.ps1"),
        "-RequestPath", _windows_path(request_path),
    ]
    options = {}
    if os.name == "nt":
        options["creationflags"] = subprocess.CREATE_NO_WINDOW
    else:
        options["start_new_session"] = True
    with log_path.open("wb") as log:
        return subprocess.Popen(
            command, stdin=subprocess.DEVNULL, stdout=log, stderr=log, **options
        )


def _error_response(request, response_path, message):
    # Never replace a response already committed by the UI.
    if not response_path.exists():
        _write_json(response_path, {
            "schema_version": 1, "request_id": request["request_id"],
            "agent": request["agent"], "status": "error", "answer": None,
            "error": message, "answered_at": _now(),
        })


def start_question(question, *, agent="unknown", title="AgentAsk", request_root=None):
    """Open one independent window; return (file metadata, subprocess handle).

    A detached caller must inspect response.json to distinguish an answer from
    cancellation. If the UI is forcibly killed, no response may be produced.
    """
    if not isinstance(question, str) or not question.strip():
        raise ValueError("Question must not be empty.")
    request_id = uuid.uuid4().hex
    directory = Path(request_root or ROOT / "requests").resolve() / request_id
    directory.mkdir(parents=True, exist_ok=False)
    request_path = directory / "request.json"
    response_path = directory / "response.json"
    log_path = directory / "ui.log"
    request = {
        "schema_version": 1, "request_id": request_id, "agent": agent,
        "title": title, "question": question, "created_at": _now(),
    }
    _write_json(request_path, request)
    metadata = {
        "request_id": request_id, "request_file": str(request_path),
        "response_file": str(response_path), "log_file": str(log_path),
    }
    try:
        process = _launch(request_path, log_path)
    except Exception as exc:
        _error_response(request, response_path, str(exc))
        raise RuntimeError("Cannot open question window; see " + str(response_path)) from exc
    return metadata, process


def read_response(response_file):
    """Return the committed response, or None while no response exists."""
    try:
        with Path(response_file).open(encoding="utf-8-sig") as stream:
            return json.load(stream)
    except FileNotFoundError:
        return None


def wait_for_response(metadata, process):
    code = process.wait()
    response = read_response(metadata["response_file"])
    if response is None:
        request = json.loads(Path(metadata["request_file"]).read_text(encoding="utf-8"))
        _error_response(request, Path(metadata["response_file"]),
                        "UI exited without a response (exit code %s). See ui.log." % code)
        response = read_response(metadata["response_file"])
    return response


def ask(question, *, agent="unknown", title="AgentAsk", request_root=None):
    """Block until the user submits/cancels or the UI process exits."""
    metadata, process = start_question(
        question, agent=agent, title=title, request_root=request_root
    )
    return wait_for_response(metadata, process)

"""File protocol and concurrent callers, without opening interactive windows."""

from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from agentask import service


class ExitedProcess:
    def wait(self):
        return 7


class ServiceTests(unittest.TestCase):
    def test_concurrent_requests_keep_answers_isolated(self):
        def fake_launch(request_path, log_path):
            request = json.loads(request_path.read_text(encoding="utf-8"))
            service._write_json(request_path.parent / "response.json", {
                "request_id": request["request_id"], "status": "answered",
                "answer": request["question"], "agent": request["agent"],
            })
            return ExitedProcess()

        with tempfile.TemporaryDirectory() as directory:
            with patch.object(service, "_launch", side_effect=fake_launch):
                with ThreadPoolExecutor(max_workers=8) as pool:
                    answers = list(pool.map(lambda i: service.ask(
                        "中文问题 %s\n`$() \\\"" % i, agent="agent-%s" % i,
                        request_root=directory), range(24)))
            self.assertEqual(24, len({item["request_id"] for item in answers}))
            for i, item in enumerate(answers):
                self.assertEqual("agent-%s" % i, item["agent"])
                self.assertEqual("中文问题 %s\n`$() \\\"" % i, item["answer"])
            self.assertEqual(24, len(list(Path(directory).glob("*/response.json"))))

    def test_crashed_ui_produces_error_instead_of_hanging(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(service, "_launch", return_value=ExitedProcess()):
                answer = service.ask("question", request_root=directory)
            self.assertEqual("error", answer["status"])
            self.assertIn("exit code 7", answer["error"])

    def test_launch_failure_is_saved(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(service, "_launch", side_effect=OSError("launch failed")):
                with self.assertRaises(RuntimeError):
                    service.ask("question", request_root=directory)
            response = next(Path(directory).glob("*/response.json"))
            self.assertEqual("error", service.read_response(response)["status"])

    def test_pending_and_cancelled_are_distinct(self):
        with tempfile.TemporaryDirectory() as directory:
            response = Path(directory) / "response.json"
            self.assertIsNone(service.read_response(response))
            service._write_json(response, {"status": "cancelled", "answer": None})
            self.assertEqual("cancelled", service.read_response(response)["status"])

    def test_empty_question_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                service.ask(" \n", request_root=directory)
            self.assertEqual([], list(Path(directory).iterdir()))


if __name__ == "__main__":
    unittest.main()

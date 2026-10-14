from contextlib import redirect_stderr, redirect_stdout
import io
import json
import unittest
from unittest.mock import patch

from agentask import cli


class CliTests(unittest.TestCase):
    def test_automatic_outcomes_have_distinct_exit_codes(self):
        for status, code in (("answered", 0), ("cancelled", 2), ("disabled", 3), ("timed_out", 4)):
            with self.subTest(status=status):
                output = io.StringIO()
                with patch.object(cli, "start_question", return_value=({"response_file": "response.json"}, None)), \
                        patch.object(cli, "wait_for_response", return_value={"status": status}), \
                        redirect_stdout(output), redirect_stderr(io.StringIO()):
                    self.assertEqual(code, cli.main(["--question", "question"]))
                self.assertEqual(status, json.loads(output.getvalue())["status"])

    def test_detached_disabled_result_is_immediate(self):
        output = io.StringIO()
        with patch.object(cli, "start_question", return_value=({"status": "disabled"}, None)), \
                patch.object(cli, "wait_for_response") as wait, redirect_stdout(output):
            self.assertEqual(0, cli.main(["--question", "question", "--detach"]))
            wait.assert_not_called()
        self.assertEqual("disabled", json.loads(output.getvalue())["status"])

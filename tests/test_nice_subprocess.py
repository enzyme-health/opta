# type: ignore
import os
from asyncio import TimeoutError
from time import sleep

import pytest

from opta.nice_subprocess import nice_run

GRACEFUL_TERMINATION_FILE = os.path.join(
    os.path.dirname(os.path.dirname(__file__)), "tests", "signal_gracefully_terminated",
)
SIGNAL_HANDLER_SCRIPT = os.path.join(
    os.path.dirname(os.path.dirname(__file__)), "tests", "signal_handler.py",
)


class TestNiceRun:
    def test_echo(self):
        completed_process = nice_run(
            ["echo", "Hello world!"],
            check=True,
            capture_output=True,
            use_asyncio_nice_run=True,
        )
        assert completed_process.returncode == 0
        assert completed_process.stdout == "Hello world!\n"

    def test_does_not_log_full_argv_or_output(self, mocker):
        # log_to_datadog's payload used to be the full command argv and the
        # full subprocess stdout, either of which can carry secrets (e.g.
        # `terraform apply -var="password=..."` or a value it prints back).
        log_spy = mocker.patch("opta.nice_subprocess.log_to_datadog")
        SECRET = "super-secret-value-xyz"

        completed_process = nice_run(
            ["echo", SECRET],
            check=True,
            capture_output=True,
            use_asyncio_nice_run=True,
        )

        assert completed_process.stdout == f"{SECRET}\n"
        logged_text = " ".join(str(call) for call in log_spy.call_args_list)
        assert SECRET not in logged_text

    def test_timeout(self):
        with pytest.raises(TimeoutError):
            nice_run(
                ["sleep", "5"],
                check=True,
                capture_output=True,
                use_asyncio_nice_run=True,
                timeout=1,
            )

    def test_graceful_timeout_exit(self):
        if os.path.exists(GRACEFUL_TERMINATION_FILE):
            os.remove(GRACEFUL_TERMINATION_FILE)

        with pytest.raises(TimeoutError):
            nice_run(
                ["python", SIGNAL_HANDLER_SCRIPT], timeout=3, use_asyncio_nice_run=True
            )
        sleep(5)
        assert os.path.exists(GRACEFUL_TERMINATION_FILE)

        # clean up
        os.remove(GRACEFUL_TERMINATION_FILE)

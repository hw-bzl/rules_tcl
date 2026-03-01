"""The TclLint action runner."""

import argparse
import io
import os
import platform
import sys
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

from python.runfiles import Runfiles
from tclint.cli.tclint import main as tclint_main


def _rlocation(runfiles: Runfiles, rlocationpath: str) -> Path:
    """Look up a runfile and ensure the file exists

    Args:
        runfiles: The runfiles object
        rlocationpath: The runfile key

    Returns:
        The requested runifle.
    """
    # TODO: https://github.com/periareon/rules_venv/issues/37
    source_repo = None
    if platform.system() == "Windows":
        source_repo = ""
    runfile = runfiles.Rlocation(rlocationpath, source_repo)
    if not runfile:
        raise FileNotFoundError(f"Failed to find runfile: {rlocationpath}")
    path = Path(runfile)
    if not path.exists():
        raise FileNotFoundError(f"Runfile does not exist: ({rlocationpath}) {path}")
    return path


def parse_args() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description=__doc__)

    argv = None

    def _lookup(value: str) -> Path:
        del value
        raise NotImplementedError()

    use_args_file = "RULES_TCL_LINT_ARGS_FILE" in os.environ
    if use_args_file:
        runfiles = Runfiles.Create()
        if not runfiles:
            raise EnvironmentError("Failed to locate runfiles.")

        def _lookup(value: str) -> Path:  # pylint: disable=function-redefined
            return _rlocation(runfiles, value)

        argv = (
            _rlocation(runfiles, os.environ["RULES_TCL_LINT_ARGS_FILE"])
            .read_text(encoding="utf-8")
            .splitlines()
        )

    parser.add_argument(
        "--src",
        dest="srcs",
        type=_lookup if use_args_file else Path,
        required=True,
        action="append",
        default=[],
        help="Sources to lint/format.",
    )
    parser.add_argument(
        "--config",
        type=_lookup if use_args_file else Path,
        required=True,
        help="The tclint config file.",
    )
    parser.add_argument(
        "--marker",
        type=Path,
        help="An optional output to touch upon successful lint/formatting.",
    )

    return parser.parse_args(argv)


def run_lint(
    config: str,
    srcs: list[str],
) -> tuple[int, str]:
    """Run a tclint tool (tclint or tclfmt) and capture its output.

    Args:
        config: Path to the config file
        srcs: List of source file paths

    Returns:
        Tuple of (return_code, captured_output)
    """
    # Build command-line arguments
    tool_args = ["tclint", "--config", str(config)] + [str(src) for src in srcs]

    output_buffer = io.StringIO()
    original_argv = sys.argv
    try:
        # Set up sys.argv for tool_main
        sys.argv = tool_args

        # Capture both stdout and stderr to the shared buffer
        with redirect_stdout(output_buffer), redirect_stderr(output_buffer):
            # Run tool main function
            # It may return a code, return None, or raise SystemExit
            return_code = 0
            try:
                result = tclint_main()
                # If it returns a value, use it; otherwise assume success
                if result is not None:
                    return_code = result
            except SystemExit as e:
                # tool_main called sys.exit(), capture the exit code
                return_code = (
                    int(e.code)
                    if isinstance(e.code, int)
                    else (0 if e.code is None else 1)
                )

        # Get the captured output
        captured_output = output_buffer.getvalue()

        return return_code, captured_output

    finally:
        # Restore original sys state
        sys.argv = original_argv


def main() -> None:
    """The main entrypoint."""
    args = parse_args()

    lint_code = 0

    # Run linting if requested (always run, even if formatting will also run)
    lint_code, lint_output = run_lint(
        args.config,
        args.srcs,
    )
    if lint_code:
        print(lint_output, file=sys.stderr)
        sys.exit(lint_code)

    # Touch marker file on success (only if both steps passed)
    if args.marker:
        args.marker.parent.mkdir(exist_ok=True, parents=True)
        args.marker.write_bytes(b"")


if __name__ == "__main__":
    main()

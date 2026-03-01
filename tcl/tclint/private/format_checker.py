"""The TclFormat action runner."""

import argparse
import difflib
import io
import os
import platform
import shutil
import sys
import tempfile
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

from python.runfiles import Runfiles
from tclint.cli.tclfmt import main as tclfmt_main


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

    use_args_file = "RULES_TCL_FORMAT_ARGS_FILE" in os.environ
    if use_args_file:
        runfiles = Runfiles.Create()
        if not runfiles:
            raise EnvironmentError("Failed to locate runfiles.")

        def _lookup(value: str) -> Path:  # pylint: disable=function-redefined
            return _rlocation(runfiles, value)

        argv = (
            _rlocation(runfiles, os.environ["RULES_TCL_FORMAT_ARGS_FILE"])
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


def run_format(
    config: Path, srcs: list[Path], extra_args: list[str]
) -> tuple[int, str]:
    """Run tclfmt with --check to see if files need formatting.

    Args:
        config: Path to the config file
        srcs: List of source file paths
        original_argv: Original sys.argv to restore
        original_stdout: Original sys.stdout to restore
        original_stderr: Original sys.stderr to restore

    Returns:
        Tuple of (return_code, captured_output)
    """
    # Build command-line arguments
    tool_args = ["tclfmt", "--config", str(config)] + [str(src) for src in srcs]
    if extra_args:
        tool_args.extend(extra_args)

    # Create shared buffer for stdout and stderr
    output_buffer = io.StringIO()
    original_argv = sys.argv

    try:
        # Set up sys.argv for tclfmt_main
        sys.argv = tool_args

        # Capture both stdout and stderr to the shared buffer
        with redirect_stdout(output_buffer), redirect_stderr(output_buffer):
            # Run tclfmt main function
            return_code = 0
            try:
                result = tclfmt_main()
                if result is not None:
                    return_code = result
            except SystemExit as e:
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


def copy_to_temp_preserving_paths(srcs: list[Path], temp_dir: Path) -> dict[Path, Path]:
    """Copy source files to temp directory preserving relative paths.

    Args:
        srcs: List of source file paths
        temp_dir: Temporary directory to copy files to

    Returns:
        Dictionary mapping original paths to temp paths
    """
    path_map = {}

    if len(srcs) == 1:
        # Single file - just copy with its name
        src_abs = srcs[0]
        temp_file = temp_dir / src_abs.name
        temp_file.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src_abs, temp_file)
        path_map[src_abs] = temp_file
    else:
        # Multiple files - find common path prefix
        common_prefix = Path(os.path.commonpath([str(p) for p in srcs]))

        for src_abs in srcs:
            try:
                # Get relative path from common prefix
                rel_path = src_abs.relative_to(common_prefix)
            except ValueError:
                # If can't get relative path, use full path structure
                # Replace path separators with underscores to avoid deep nesting
                path_parts = src_abs.parts
                rel_path = Path(*path_parts[-2:])  # Use last two parts

            # Create temp file preserving relative structure
            temp_file = temp_dir / rel_path

            # Create parent directories
            temp_file.parent.mkdir(parents=True, exist_ok=True)

            # Copy file
            shutil.copy2(src_abs, temp_file)
            path_map[src_abs] = temp_file

    return path_map


def generate_diff(original_path: Path, formatted_path: Path) -> str:
    """Generate a unified diff between original and formatted file.

    Args:
        original_path: Path to the original file
        formatted_path: Path to the formatted file

    Returns:
        Diff string
    """
    original_lines = original_path.read_text(encoding="utf-8").splitlines()
    formatted_lines = formatted_path.read_text(encoding="utf-8").splitlines()

    diff = difflib.unified_diff(
        original_lines,
        formatted_lines,
        fromfile=str(original_path),
        tofile=f"{original_path} - formatted",
        lineterm="",
    )

    return "\n".join(diff)


def main() -> int:
    """The main entrypoint.

    Returns:
        Exit code (0 for success, non-zero for failure)
    """
    args = parse_args()

    # First, run format check
    check_code, check_output = run_format(
        args.config,
        args.srcs,
        ["--check"],
    )

    # If check passes, we're done
    if check_code == 0:
        # Touch marker file on success
        if args.marker:
            args.marker.parent.mkdir(exist_ok=True, parents=True)
            args.marker.write_bytes(b"")
        sys.exit(0)

    print(check_output, file=sys.stderr)

    # Check failed, so we need to format and show diff
    # Create temporary directory
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)

        # Copy source files to temp directory preserving paths
        path_map = copy_to_temp_preserving_paths(args.srcs, temp_path)

        # Get list of temp file paths
        temp_srcs = sorted(path_map.values())

        # Run format tool on copied files (without --check)
        fmt_code, fmt_output = run_format(
            args.config,
            temp_srcs,
            ["--in-place"],
        )

        if fmt_code != 0:
            print(fmt_output, file=sys.stderr)
            sys.exit(fmt_code)

        # Generate and print diffs for each file
        for original_path, temp_path_mapped in path_map.items():
            diff = generate_diff(original_path, temp_path_mapped)
            if diff:
                print(diff, file=sys.stderr)

    # Return error code since formatting was needed
    sys.exit(1)


if __name__ == "__main__":
    main()

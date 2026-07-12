#!/usr/bin/env python3
"""
Dev server lifecycle manager for E2E tests.

Starts one or more dev servers, waits until each port is ready, runs the
test command, then kills all servers. Exit code mirrors the test command.

Usage:
    python3 with_server.py --cmd "npm run dev" --port 3000 --test-cmd "npx playwright test"
    python3 with_server.py --cmd "npm run dev" --port 3000 --cmd "npm run api" --port 8080 --test-cmd "npx playwright test"
    python3 with_server.py --cmd "npm run dev" --port 3000 --test-cmd "npx playwright test" --timeout 60 --cwd /path/to/project

Cross-platform (macOS + Linux). Python 3.8+, no pip dependencies.
"""

import argparse
import os
import signal
import socket
import subprocess
import sys
import time


def parse_args():
    """Parse command-line arguments with support for repeated --cmd/--port pairs."""
    parser = argparse.ArgumentParser(
        description="Manage dev server lifecycle for E2E tests.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Single server
  %(prog)s --cmd "npm run dev" --port 3000 --test-cmd "npx playwright test"

  # Multiple servers (frontend + API)
  %(prog)s --cmd "npm run dev" --port 3000 \\
           --cmd "npm run api" --port 8080 \\
           --test-cmd "npx playwright test"

  # Custom timeout and working directory
  %(prog)s --cmd "npm run dev" --port 3000 \\
           --test-cmd "npx playwright test" \\
           --timeout 60 --cwd /path/to/project
""",
    )
    parser.add_argument(
        "--cmd",
        action="append",
        required=True,
        help="Server command to run. Can be repeated for multiple servers.",
    )
    parser.add_argument(
        "--port",
        action="append",
        type=int,
        required=True,
        help="Port to wait for. Must match the number of --cmd arguments.",
    )
    parser.add_argument(
        "--test-cmd",
        required=True,
        help="Test command to run after all servers are ready.",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=30,
        help="Max seconds to wait for each server (default: 30).",
    )
    parser.add_argument(
        "--cwd",
        default=None,
        help="Working directory for all commands (default: current directory).",
    )

    args = parser.parse_args()

    if len(args.cmd) != len(args.port):
        parser.error(
            f"Number of --cmd ({len(args.cmd)}) must match "
            f"number of --port ({len(args.port)})."
        )

    return args


def is_port_open(host, port):
    """Check if a TCP port is accepting connections."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(1)
    try:
        result = sock.connect_ex((host, port))
        return result == 0
    except (socket.error, OSError):
        return False
    finally:
        sock.close()


def wait_for_port(port, timeout, label="server"):
    """Poll a port until it accepts connections or timeout is reached."""
    start = time.monotonic()
    interval = 0.5
    while time.monotonic() - start < timeout:
        if is_port_open("127.0.0.1", port):
            elapsed = time.monotonic() - start
            print(f"[with_server] {label} ready on port {port} ({elapsed:.1f}s)")
            return True
        time.sleep(interval)
        # Gradually increase polling interval to reduce overhead
        if interval < 2.0:
            interval = min(interval * 1.5, 2.0)
    return False


def kill_process_tree(proc):
    """Kill a process and its children. Works on macOS and Linux."""
    if proc.poll() is not None:
        return  # Already dead

    pid = proc.pid
    try:
        # Try to kill the process group (catches child processes)
        os.killpg(os.getpgid(pid), signal.SIGTERM)
    except (ProcessLookupError, PermissionError, OSError):
        # Fallback: kill just the process
        try:
            proc.terminate()
        except (ProcessLookupError, OSError):
            pass

    # Wait briefly for graceful shutdown
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        # Force kill
        try:
            os.killpg(os.getpgid(pid), signal.SIGKILL)
        except (ProcessLookupError, PermissionError, OSError):
            try:
                proc.kill()
            except (ProcessLookupError, OSError):
                pass


def main():
    args = parse_args()
    cwd = args.cwd or os.getcwd()
    servers = []
    test_exit_code = 1

    # Set up signal handlers for cleanup
    def cleanup(signum=None, frame=None):
        print(f"\n[with_server] Cleaning up {len(servers)} server(s)...")
        for proc, cmd in servers:
            print(f"[with_server] Stopping: {cmd}")
            kill_process_tree(proc)
        if signum is not None:
            sys.exit(128 + signum)

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)

    try:
        # Start all servers
        for cmd, port in zip(args.cmd, args.port):
            print(f"[with_server] Starting: {cmd} (expecting port {port})")
            proc = subprocess.Popen(
                cmd,
                shell=True,
                cwd=cwd,
                # Start new process group so we can kill the tree
                preexec_fn=os.setsid,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
            )
            servers.append((proc, cmd))

        # Wait for all ports to be ready
        for (proc, cmd), port in zip(servers, args.port):
            # Check if server process died during startup
            if proc.poll() is not None:
                stdout = proc.stdout.read().decode("utf-8", errors="replace")
                print(
                    f"[with_server] ERROR: Server exited immediately "
                    f"(exit code {proc.returncode}): {cmd}"
                )
                if stdout.strip():
                    print(f"[with_server] Output:\n{stdout[:2000]}")
                cleanup()
                sys.exit(1)

            label = f"'{cmd}'"
            if not wait_for_port(port, args.timeout, label=label):
                print(
                    f"[with_server] ERROR: Timeout ({args.timeout}s) waiting "
                    f"for port {port} from: {cmd}"
                )
                # Print server output for debugging
                proc.terminate()
                try:
                    stdout, _ = proc.communicate(timeout=3)
                    output = stdout.decode("utf-8", errors="replace")
                    if output.strip():
                        print(f"[with_server] Server output:\n{output[:2000]}")
                except subprocess.TimeoutExpired:
                    pass
                cleanup()
                sys.exit(1)

        # All servers ready — run tests
        print(f"[with_server] All servers ready. Running: {args.test_cmd}")
        print("-" * 60)

        test_proc = subprocess.run(cmd=args.test_cmd, shell=True, cwd=cwd)
        test_exit_code = test_proc.returncode

        print("-" * 60)
        if test_exit_code == 0:
            print("[with_server] Tests PASSED")
        else:
            print(f"[with_server] Tests FAILED (exit code {test_exit_code})")

    finally:
        cleanup()

    sys.exit(test_exit_code)


if __name__ == "__main__":
    main()

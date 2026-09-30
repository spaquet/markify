#!/usr/bin/env python3
"""Local launcher checks; no model requests or changes to installed agent settings."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory(prefix="markify agents ") as temporary:
    folder = Path(temporary)
    fake = folder / "fake markify"
    fake.write_text("""#!/usr/bin/env python3
import json, os, sys
if sys.argv[1:] == ['--help']:
    print('markify view' if not os.environ.get('OLD_CLI') else 'markify check')
    sys.exit(0)
with open(os.environ['CAPTURE'], 'w') as output:
    json.dump({'args': sys.argv[1:], 'text': sys.stdin.read()}, output)
sys.exit(int(os.environ.get('FAIL_CLI', '0')))
""")
    fake.chmod(0o700)
    capture = folder / "capture.json"
    env = dict(os.environ, MARKIFY_CLI=str(fake), CAPTURE=str(capture))
    report = "# café 🌻\n\n$(touch never) `literal`\nNo final newline"
    launcher = ROOT / "agents/claude/scripts/view.sh"
    result = subprocess.run(["bash", str(launcher), "-", "--title", "A & B", "--base", str(folder)], input=report, text=True, env=env, capture_output=True)
    assert result.returncode == 0, result.stderr
    received = json.loads(capture.read_text())
    assert received == {"args": ["view", "-", "--title", "A & B", "--base", str(folder)], "text": report}
    for extra in [{"MARKIFY_CLI": str(folder / "missing")}, {"OLD_CLI": "1"}, {"FAIL_CLI": "1"}]:
        result = subprocess.run(["bash", str(launcher), "-"], input=report, text=True, env=dict(env, **extra), capture_output=True)
        assert result.returncode != 0
        if "FAIL_CLI" not in extra:
            assert "https://github.com/spaquet/markify/releases/latest" in result.stderr
    if shutil.which("jq"):
        hook = ["bash", str(ROOT / "agents/claude/scripts/stop.sh")]
        payload = {"last_assistant_message": report, "cwd": str(folder), "stop_hook_active": False}
        result = subprocess.run(hook, input=json.dumps(payload), text=True, env=env, capture_output=True)
        assert result.returncode == 0, result.stderr
        assert json.loads(capture.read_text())["text"] == report
        capture.unlink()
        payload["stop_hook_active"] = True
        assert subprocess.run(hook, input=json.dumps(payload), text=True, env=env).returncode == 0
        assert not capture.exists()
        payload["stop_hook_active"] = False
        assert subprocess.run(hook, input=json.dumps(payload), text=True, env=dict(env, FAIL_CLI="1"), capture_output=True).returncode == 0
    else:
        print("Optional Stop hook checks skipped: jq is not installed.")

print("Agent launcher checks passed.")

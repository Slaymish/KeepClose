#!/usr/bin/env python3
"""CLI integration checks; writes only to a temporary dataset."""
import concurrent.futures
import json
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
subprocess.run(["swift", "build", "--product", "keepclose"], cwd=root, check=True)
binary = str(root / ".build/debug/keepclose")
with tempfile.TemporaryDirectory(prefix="keepclose-test-") as directory:
    def run(*args, ok=True):
        result = subprocess.run([binary, *args, "--data-dir", directory], capture_output=True, text=True)
        if ok:
            assert result.returncode == 0, result.stderr
            return json.loads(result.stdout)
        assert result.returncode != 0, args

    person = run("add", "--name", "Test person", "--days", "7", "--context", "Ask about the garden")
    uid = person["id"]
    run("update", uid, "--circle", "Family", "--method", "email", "--address", "example@example.com")
    assert run("show", uid)["context"] == "Ask about the garden"
    run("snooze", uid, "--days", "3")
    assert run("due") == []
    run("pause", uid)
    assert run("show", uid)["paused"]
    run("resume", uid)
    assert not run("show", uid)["paused"]
    run("log", uid, "--note", "Caught up")
    assert run("show", uid)["deferrals"] == 0
    run("update", uid, "--types", "Friend,Colleague", "--contexts", "Work,Online", "--intention", "grow")
    changed = run("show", uid)
    assert changed["relationshipTypes"] == ["Friend", "Colleague"]
    assert changed["contexts"] == ["Work", "Online"]
    assert changed["rhythmDays"] == 7  # A custom rhythm is preserved.
    run("update", uid, "--rhythm", "auto")
    assert not run("show", uid)["rhythmIsCustom"]
    run("log", uid, "--kind", "incoming")
    assert run("suggest", uid)["suggestion"]["action"] == "reply"
    assert run("suggestions")[0]["suggestion"]["ready"]
    run("log", uid, "--kind", "reply")
    assert run("suggest", uid)["suggestion"]["action"] == "later"
    run("update", uid, "--intention", "space")
    assert run("suggest", uid)["suggestion"]["action"] == "giveSpace"
    run("log", uid, "--kind", "incoming")
    incoming = run("show", uid)["contacts"][-1]["id"]
    run("resolve", uid, "--entry", incoming)
    assert run("suggest", uid)["suggestion"]["action"] == "giveSpace"
    run("log", uid, "--kind", "ambient")
    run("log", uid, "--kind", "conversation", "--initiator", "them")
    run("log", uid, "--kind", "incoming", "--initiator", "me", ok=False)
    run("update", uid, "--intention", "invalid", ok=False)
    run("update", uid, "--rhythm", "auto", "--days", "5", ok=False)
    run("reminders", "on", "--time", "09:30", "--names", "never")
    assert run("reminders")["requested"]["hour"] == 9
    assert not run("reminders")["requested"]["includeNames"]
    run("reminders", "on", "--time", "09:30", "--names", "invalid", ok=False)
    run("reminders", "off")
    assert not run("reminders")["requested"]["enabled"]
    run("delete", uid, ok=False)
    assert len(run("list")) == 1
    run("update", uid, "--days", "0", ok=False)
    import_file = pathlib.Path(directory) / "agent-import.json"
    import_file.write_text(json.dumps({"version": 1, "source": "claude", "people": [
        {"name": "Imported friend", "types": ["Friend"], "contexts": ["Hobby"], "notes": "Likes gardening"},
        {"id": uid, "name": "Test person", "notes": "More context from memory", "intention": "grow"}
    ]}))
    stored = pathlib.Path(directory) / "relationships.json"
    before = stored.read_bytes()
    preview = run("import", str(import_file), "--dry-run")
    assert preview["added"] == 1 and preview["updated"] == 1
    assert stored.read_bytes() == before
    applied = run("import", str(import_file), "--apply")
    assert applied["added"] == 1 and applied["updated"] == 1
    assert pathlib.Path(applied["backupPath"]).read_bytes() == before
    assert run("show", uid)["intention"] == "space"  # Existing intent is preserved.
    repeated = run("import", str(import_file), "--apply")
    assert repeated["unchanged"] == 2 and repeated.get("backupPath") is None
    imported_id = next(person["id"] for person in run("list") if person["name"] == "Imported friend")
    run("delete", imported_id, "--yes")
    bad = pathlib.Path(directory) / "bad-import.json"
    bad.write_text(json.dumps({"version": 1, "source": "chatgpt", "people": [{"name": "Bad", "contacts": []}]}))
    before = stored.read_bytes()
    run("import", str(bad), "--apply", ok=False)
    assert stored.read_bytes() == before
    run("import", str(import_file), "--apply", "--dry-run", ok=False)
    assert "--apply" in run("import-prompt", "--source", "chatgpt")["prompt"]
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(lambda i: run("add", "--name", "Concurrent %s" % i), range(30)))
    assert len(run("list")) == 31
    run("delete", uid, "--yes")
    assert len(run("list")) == 30
print("CLI lifecycle, agent imports, validation, reminders and 30 concurrent process writes passed.")

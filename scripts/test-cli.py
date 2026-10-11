#!/usr/bin/env python3
"""CLI integration checks; writes only to a temporary dataset."""
import concurrent.futures
import datetime
import json
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
# --disable-sandbox lets SwiftPM run on hosts where a nested sandbox is unavailable.
subprocess.run(["swift", "build", "--product", "keepclose", "--disable-sandbox"], cwd=root, check=True)
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
    run("update", uid, "--birthday", "02-29", "--gift-reminder", "off")
    assert run("show", uid)["birthday"] == {"month": 2, "day": 29}
    run("update", uid, "--birthday", "2001-02-29", ok=False)
    assert run("show", uid)["birthday"]["day"] == 29
    duplicate = run("add", "--name", "Duplicate example", "--birthday", "1992-03-04", "--notes", "Second note")
    duplicate_id = duplicate["id"]
    run("log", duplicate_id, "--kind", "conversation", "--note", "Shared dinner")
    preview = run("merge", duplicate_id, "--into", uid, "--birthday", "source")
    assert preview["birthday"] == {"month": 3, "day": 4, "year": 1992}
    assert len(run("list")) == 2, "Preview must not change data"
    merged = run("merge", duplicate_id, "--into", uid, "--birthday", "source", "--yes")
    assert merged["id"] == uid and duplicate_id in merged["mergedPersonIDs"]
    assert merged["contacts"][0]["note"] == "Shared dinner" and "Second note" in merged["context"]
    assert len(run("list")) == 1
    assert list(pathlib.Path(directory, "backups").glob("before-merge-*.json"))
    run("update", uid, "--birthday", "none")
    assert "birthday" not in run("show", uid)
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
    assert '"version": 2' in run("import-prompt", "--source", "chatgpt")["prompt"]

    # Recorded context: ideas, interests, memories and rituals, with provenance intact.
    # Offering ideas is separate from giving space: switch back to maintain first.
    run("update", uid, "--intention", "maintain")
    run("interest", uid, "--add", "--name", "Board games", "--detail", "Owns a stack")
    run("memory", uid, "--add", "--text", "An evening we both enjoyed")
    run("ritual", uid, "--add", "--title", "Thursday game night", "--days", "7")
    added = run("idea", uid, "--add", "--activity", "an evening of board games", "--kind", "sharedActivity", "--timing", "weekend", "--reason", "You both enjoy board games")
    assert added["action"] == "add"
    idea = added["ideas"][0]
    assert idea["sources"] == ["me"] and idea["confidence"] == "known"
    context = run("context", uid)
    assert len(context["person"]["connection"]["ideas"]) == 1
    assert context["person"]["connection"]["interests"][0]["name"] == "Board games"
    assert any(opportunity["ideaId"] == idea["id"] for opportunity in context["opportunities"])
    assert run("suggest", uid)["suggestion"]["opportunity"]["activity"] == "an evening of board games"
    run("idea", uid, "--edit", "--idea", idea["id"], "--reminder", "Board games at mine?", "--cadence", "21")
    assert run("show", uid)["connection"]["ideas"][0]["reminder"] == "Board games at mine?"
    run("useful", uid, "--idea", idea["id"])
    assert run("show", uid)["feedback"][-1]["signal"] == "helpful"
    run("pass", uid, "--idea", idea["id"])
    passed = run("show", uid)
    assert passed["connection"]["ideas"][0]["dismissed"]
    assert passed["feedback"][-1]["signal"] == "notForMe"
    assert run("context", uid)["opportunities"] == []
    run("idea", uid, "--restore", "--idea", idea["id"])
    assert not run("show", uid)["connection"]["ideas"][0]["dismissed"]
    assert any(item["ideaId"] == idea["id"] for item in run("context", uid)["opportunities"]), "Explicit restoration makes the idea available again."
    first_memory = run("memory", uid, "--add", "--text", "A remembered evening from a shared trip", "--source", "agent", "--confidence", "suggested")
    assert first_memory["action"] == "add"
    run("memory", uid, "--add", "--text", "A completely different note about a phone call")
    memories = run("show", uid)["connection"]["memories"]
    assert len(memories) == 3, "Distinct memories accumulate; only real duplicates merge."
    assert sum(1 for memory in memories if memory["confidence"] == "suggested") == 1
    run("memory", uid, "--edit", "--memory", first_memory["memories"][0]["id"], "--text", "An edited recollection")
    edited = next(memory for memory in run("show", uid)["connection"]["memories"] if memory["text"] == "An edited recollection")
    assert edited["sources"] == ["me"] and edited["confidence"] == "known", "A hand edit replaces provenance with the user's own."
    run("memory", uid, "--forget", "--memory", edited["id"])
    assert len(run("show", uid)["connection"]["memories"]) == 2
    interest_id = run("show", uid)["connection"]["interests"][0]["id"]
    run("interest", uid, "--remove", "--interest", interest_id)
    assert run("show", uid)["connection"]["interests"] == []
    ritual_id = run("show", uid)["connection"]["rituals"][0]["id"]
    run("ritual", uid, "--remove", "--ritual", ritual_id)
    assert run("show", uid)["connection"]["rituals"] == []
    run("update", uid, "--intention", "space")
    assert run("context", uid)["opportunities"] == []
    run("update", uid, "--intention", "maintain")
    run("idea", uid, "--dismiss", "--idea", idea["id"])
    run("idea", uid, "--remove", "--idea", idea["id"])
    assert run("show", uid)["connection"]["ideas"] == []
    run("idea", uid, "--add", "--activity", "a walk", "--kind", "invalid", ok=False)
    run("memory", uid, "--add", "--text", "x", "--source", "psychic", ok=False)
    run("pass", uid, "--idea", "not-a-uuid", ok=False)

    # Connection lifecycle: an invitation is not the activity, and future plans are not logs.
    lifecycle_idea = run("idea", uid, "--add", "--activity", "an evening of board games")
    idea = lifecycle_idea["ideas"][0]
    before_contacts = len(run("show", uid)["contacts"])
    sent = run("log", uid, "--kind", "outreach", "--idea", idea["id"], "--note", "Invitation sent")
    sent_id = sent["contacts"][-1]["id"]
    assert sent["contacts"][-1]["ideaId"] == idea["id"]
    assert run("context", uid)["opportunities"] == []
    assert not run("suggest", uid)["suggestion"]["ready"]
    run("resolve", uid, "--entry", sent_id)
    assert len(run("show", uid)["contacts"]) == before_contacts + 1
    run("unlog", uid, "--entry", sent_id)
    future = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=5)).isoformat(timespec="seconds")
    planned = run("plan", uid, "--title", "A game evening", "--at", future, "--idea", idea["id"])
    plan_id = planned["plans"][-1]["id"]
    assert len(planned["contacts"]) == before_contacts
    assert run("context", uid)["opportunities"] == []
    run("plan", uid, "--complete", plan_id, "--at", future, ok=False)
    run("plan", uid, "--cancel", plan_id, "--title", "Invalid", ok=False)
    finished = run("plan", uid, "--complete", plan_id)
    assert finished["contacts"][-1]["kind"] == "conversation"
    assert finished["plans"][-1]["status"] == "happened"
    run("unlog", uid, "--entry", finished["contacts"][-1]["id"])
    assert run("show", uid)["plans"][-1]["status"] == "planned"
    run("plan", uid, "--cancel", plan_id)
    assert run("show", uid)["plans"][-1]["status"] == "cancelled"
    run("idea", uid, "--remove", "--idea", idea["id"])

    # Version 2 imports carry contextual ideas, respect dismissals and never duplicate.
    v2_file = pathlib.Path(directory) / "agent-import-v2.json"
    remembered = "A remembered evening from a trip we took together"
    v2_file.write_text(json.dumps({"version": 2, "source": "chatgpt", "people": [{
        "id": uid, "name": "Test person",
        "context": {"confidence": "unsure", "source": "memory", "memories": [remembered],
                    "interests": [{"name": "Board games"}],
                    "ideas": [{"activity": "an evening of board games", "reason": "You both enjoy them", "source": "memory"}]}
    }]}))
    v2_preview = run("import", str(v2_file), "--dry-run")
    assert v2_preview["newIdeas"] == 1 and v2_preview["changes"][0]["action"] == "merge"
    assert run("import", str(v2_file), "--apply")["newIdeas"] == 1
    stored_person = run("show", uid)
    imported_idea = next(idea for idea in stored_person["connection"]["ideas"] if idea["activity"] == "an evening of board games")
    assert imported_idea["confidence"] == "unsure", "Imported context is never presented as certain."
    assert imported_idea["sources"] == ["memory"]
    imported_memory = next(memory for memory in stored_person["connection"]["memories"] if memory["text"] == remembered)
    assert imported_memory["confidence"] == "unsure" and imported_memory["sources"] == ["memory"]
    idea_id = imported_idea["id"]
    run("pass", uid, "--idea", idea_id)
    dismissed_again = run("import", str(v2_file), "--dry-run")
    assert dismissed_again["newIdeas"] == 0
    assert dismissed_again["changes"][0]["dismissedIdeas"] == ["an evening of board games"]
    assert run("import", str(v2_file), "--apply")["updated"] == 0
    assert next(idea for idea in run("show", uid)["connection"]["ideas"] if idea["id"] == idea_id)["dismissed"]
    # A dismissed idea on a person whose intention the app now holds stays dismissed.
    assert run("show", uid)["intentionChosen"]
    assert run("show", uid)["intention"] == "maintain"
    bad_v2 = pathlib.Path(directory) / "bad-v2.json"
    bad_v2.write_text(json.dumps({"version": 2, "source": "chatgpt", "people": [{"name": "Bad", "context": {"ideas": [{"activity": "a walk", "photos": []}]}}]}))
    before = stored.read_bytes()
    run("import", str(bad_v2), "--apply", ok=False)
    assert stored.read_bytes() == before
    third_version = pathlib.Path(directory) / "future.json"
    third_version.write_text(json.dumps({"version": 3, "source": "chatgpt", "people": []}))
    run("import", str(third_version), "--apply", ok=False)
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(lambda i: run("add", "--name", "Concurrent %s" % i), range(30)))
    assert len(run("list")) == 31
    run("delete", uid, "--yes")
    assert len(run("list")) == 30
print("CLI lifecycle, agent imports, validation, reminders and 30 concurrent process writes passed.")

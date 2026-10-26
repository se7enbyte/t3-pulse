"""Exercise the real Swift reader against a disposable T3-shaped database."""
import datetime
import json
import os
import pathlib
import sqlite3
import subprocess
import tempfile

binary = pathlib.Path(__file__).resolve().parents[1] / "build/T3 Pulse.app/Contents/MacOS/T3Pulse"
now = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
with tempfile.TemporaryDirectory(prefix="t3pulse-check-") as root:
    userdata = pathlib.Path(root) / "userdata"
    userdata.mkdir()
    db = sqlite3.connect(userdata / "statev2.sqlite")
    db.executescript("""
    CREATE TABLE orchestration_v2_projection_threads(thread_id TEXT,title TEXT,payload_json TEXT,project_id TEXT,provider_instance_id TEXT,default_provider TEXT,deleted_at TEXT,archived_at TEXT,updated_at TEXT);
    CREATE TABLE projection_projects(project_id TEXT,title TEXT);
    CREATE TABLE orchestration_v2_projection_runs(run_id TEXT,thread_id TEXT,ordinal INTEGER,status TEXT,requested_at TEXT,completed_at TEXT,payload_json TEXT);
    CREATE TABLE orchestration_v2_projection_runtime_requests(thread_id TEXT,status TEXT,kind TEXT,payload_json TEXT);
    CREATE TABLE orchestration_v2_projection_subagents(subagent_id TEXT,thread_id TEXT,child_thread_id TEXT,status TEXT,started_at TEXT,completed_at TEXT,payload_json TEXT,provider TEXT,updated_at TEXT);
    """)
    def thread(id, archived=None):
        db.execute("INSERT INTO orchestration_v2_projection_threads VALUES(?,?,?,?,?,?,?,?,?)", (id,id,"{}","p","codex","codex",None,archived,now))
    def run(id, ordinal, state):
        db.execute("INSERT INTO orchestration_v2_projection_runs VALUES(?,?,?,?,?,?,?)", (f"{id}-{ordinal}",id,ordinal,state,now,now if state == "completed" else None,"{}"))
    thread("live")
    run("live",1,"failed")
    run("live",2,"running")
    thread("done")
    run("done",1,"completed")
    thread("archived",now)
    run("archived",1,"running")
    db.execute("INSERT INTO orchestration_v2_projection_subagents VALUES(?,?,?,?,?,?,?,?,?)", ("native","live",None,"running",now,None,json.dumps({"name":"Native child"}),"codex",now))
    db.execute("INSERT INTO orchestration_v2_projection_subagents VALUES(?,?,?,?,?,?,?,?,?)", ("visible","live","done","completed",now,now,"{}","codex",now))
    def check():
        db.commit()
        return subprocess.check_output([str(binary),"--check"],env={**os.environ,"T3CODE_HOME":root},text=True)
    output = check()
    assert "working\tlive" in output and "completed\tdone" in output
    assert "Native child" in output and "archived" not in output
    assert "OK: 3 iş" in output, output
    db.execute("INSERT INTO orchestration_v2_projection_runtime_requests VALUES(?,?,?,?)", ("live","pending","exec_command_approval","{}"))
    assert "waiting\tlive" in check()
    db.execute("DELETE FROM orchestration_v2_projection_runtime_requests")
    db.execute("INSERT INTO orchestration_v2_projection_runtime_requests VALUES(?,?,?,?)", ("live","pending","user_input",'{"blocking":false}'))
    assert "working\tlive" in check(), "Nonblocking questions must not hide active work"
    db.execute("UPDATE orchestration_v2_projection_runtime_requests SET payload_json='{}'")
    assert "waiting\tlive" in check()
    db.execute("DELETE FROM orchestration_v2_projection_runtime_requests")
    db.execute("UPDATE orchestration_v2_projection_runs SET status='completed',completed_at=? WHERE run_id='live-2'",(now,))
    assert "completed\tlive" in check()
    db.close()
    print("PASS: latest run, completion transition, approvals, blocking/nonblocking input, archive filter, native subagent, child deduplication.")

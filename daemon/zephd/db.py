"""SQLite database layer for persistent task storage."""

from __future__ import annotations

import json
from pathlib import Path

import aiosqlite

from .models import Task, TaskCreate, TaskStatus, TaskUpdate

DB_DIR = Path.home() / ".zephyrus" / "state"
DB_PATH = DB_DIR / "tasks.db"

SCHEMA = """
CREATE TABLE IF NOT EXISTS tasks (
    id          TEXT PRIMARY KEY,
    title       TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    status      TEXT NOT NULL DEFAULT 'pending',
    priority    INTEGER NOT NULL DEFAULT 5,
    created_by  TEXT NOT NULL DEFAULT 'user',
    assigned_to TEXT,
    depends_on  TEXT NOT NULL DEFAULT '[]',
    branch      TEXT,
    worktree    TEXT,
    tags        TEXT NOT NULL DEFAULT '[]',
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL,
    output      TEXT
);

CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_priority ON tasks(priority);
CREATE INDEX IF NOT EXISTS idx_tasks_assigned ON tasks(assigned_to);
"""


class Database:
    def __init__(self, db_path: Path = DB_PATH) -> None:
        self.db_path = db_path
        self._db: aiosqlite.Connection | None = None

    async def connect(self) -> None:
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._db = await aiosqlite.connect(str(self.db_path))
        self._db.row_factory = aiosqlite.Row
        await self._db.executescript(SCHEMA)
        await self._db.commit()

    async def close(self) -> None:
        if self._db:
            await self._db.close()

    @property
    def db(self) -> aiosqlite.Connection:
        assert self._db is not None, "Database not connected"
        return self._db

    def _row_to_task(self, row: aiosqlite.Row) -> Task:
        d = dict(row)
        d["depends_on"] = json.loads(d["depends_on"])
        d["tags"] = json.loads(d["tags"])
        return Task(**d)

    # --- CRUD ---

    async def insert_task(self, task: Task) -> Task:
        await self.db.execute(
            """INSERT INTO tasks
               (id, title, description, status, priority, created_by,
                assigned_to, depends_on, branch, worktree, tags,
                created_at, updated_at, output)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                task.id,
                task.title,
                task.description,
                task.status.value,
                task.priority,
                task.created_by,
                task.assigned_to,
                json.dumps(task.depends_on),
                task.branch,
                task.worktree,
                json.dumps(task.tags),
                task.created_at.isoformat(),
                task.updated_at.isoformat(),
                task.output,
            ),
        )
        await self.db.commit()
        return task

    async def get_task(self, task_id: str) -> Task | None:
        cursor = await self.db.execute("SELECT * FROM tasks WHERE id = ?", (task_id,))
        row = await cursor.fetchone()
        return self._row_to_task(row) if row else None

    async def list_tasks(
        self,
        status: TaskStatus | None = None,
        assigned_to: str | None = None,
        tag: str | None = None,
    ) -> list[Task]:
        query = "SELECT * FROM tasks WHERE 1=1"
        params: list = []

        if status is not None:
            query += " AND status = ?"
            params.append(status.value)
        if assigned_to is not None:
            query += " AND assigned_to = ?"
            params.append(assigned_to)

        query += " ORDER BY priority ASC, created_at ASC"

        cursor = await self.db.execute(query, params)
        rows = await cursor.fetchall()
        tasks = [self._row_to_task(r) for r in rows]

        if tag is not None:
            tasks = [t for t in tasks if tag in t.tags]

        return tasks

    async def update_task(self, task_id: str, update: TaskUpdate) -> Task | None:
        task = await self.get_task(task_id)
        if not task:
            return None

        changes = update.model_dump(exclude_none=True)
        if not changes:
            return task

        from datetime import datetime, timezone

        changes["updated_at"] = datetime.now(timezone.utc).isoformat()

        set_clauses = []
        params = []
        for key, value in changes.items():
            if key in ("depends_on", "tags"):
                value = json.dumps(value)
            elif key == "status":
                value = value.value if isinstance(value, TaskStatus) else value
            set_clauses.append(f"{key} = ?")
            params.append(value)

        params.append(task_id)
        await self.db.execute(
            f"UPDATE tasks SET {', '.join(set_clauses)} WHERE id = ?",
            params,
        )
        await self.db.commit()
        return await self.get_task(task_id)

    async def delete_task(self, task_id: str) -> bool:
        cursor = await self.db.execute("DELETE FROM tasks WHERE id = ?", (task_id,))
        await self.db.commit()
        return cursor.rowcount > 0

    async def pop_task(self, agent_id: str) -> Task | None:
        """Claim the highest-priority pending task whose dependencies are all done."""
        pending = await self.list_tasks(status=TaskStatus.PENDING)

        for task in pending:
            if task.depends_on:
                deps_met = True
                for dep_id in task.depends_on:
                    dep = await self.get_task(dep_id)
                    if not dep or dep.status != TaskStatus.DONE:
                        deps_met = False
                        break
                if not deps_met:
                    continue

            update = TaskUpdate(status=TaskStatus.CLAIMED, assigned_to=agent_id)
            return await self.update_task(task.id, update)

        return None

"""统计埋点：批量上报。

客户端离线优先，事件先攒在内存队列，攒够 20 条或退出时一次性 POST 上来；
服务端把这批写进 events 表，写失败就整批退回，客户端下次重发。
"""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field, field_validator
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import GameEvent

router = APIRouter(tags=["events"])

# 单批上限。客户端 BATCH_SIZE 是 20，这里留出余量，同时挡住"一次灌十万条"的请求。
MAX_BATCH = 50


class EventIn(BaseModel):
    event: str = Field(..., min_length=1, max_length=64)
    data: dict = Field(default_factory=dict)
    ts: float | None = Field(default=None, description="客户端时间戳，Unix 秒")


class EventBatch(BaseModel):
    events: list[EventIn] = Field(default_factory=list)

    @field_validator("events")
    @classmethod
    def _limit_size(cls, value: list[EventIn]) -> list[EventIn]:
        if len(value) > MAX_BATCH:
            raise ValueError(f"单批最多 {MAX_BATCH} 条，收到 {len(value)} 条")
        return value


def _to_datetime(ts: float | None) -> datetime | None:
    """客户端时间戳转成库里用的无时区时间（库中 created_at 是 DATETIME）。"""
    if ts is None:
        return None
    try:
        return datetime.fromtimestamp(ts, tz=timezone.utc).replace(tzinfo=None)
    except (OverflowError, OSError, ValueError):
        return None


@router.post("/events")
def report_events(batch: EventBatch, db: Session = Depends(get_db)) -> dict:
    """写入一批事件。未登录时 user_id 留空（鉴权在 M2 接上后再填）。"""
    rows: list[GameEvent] = []
    for item in batch.events:
        payload = dict(item.data)
        if item.ts is not None:
            payload["client_ts"] = item.ts

        row = GameEvent(event=item.event, payload=payload)
        created = _to_datetime(item.ts)
        if created is not None:
            row.created_at = created
        rows.append(row)

    if rows:
        db.add_all(rows)
        db.commit()

    return {"accepted": len(rows)}

"""远程存档。

单机游戏没有登录界面，所以存档按"设备"归属：客户端在本地生成一个设备 id，
每次请求带 X-Device-Id。服务端第一次见到这个 id 时建一个匿名 users 行
（用户名前缀 device:，密码占位不可登录），后续账号体系接上时再合并。
"""
from datetime import datetime

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import SaveData, User

router = APIRouter(tags=["saves"])

# 与客户端 MAX_SLOTS=3 对齐
MAX_SLOT_INDEX = 2

DEVICE_ID_MIN = 8
DEVICE_ID_MAX = 64
ANONYMOUS_PREFIX = "device:"


def _rev_of(row: SaveData) -> int:
    """版本号存在 save_data 里，不动表结构。"""
    return int((row.save_data or {}).get("_rev", 0))


class SavePayload(BaseModel):
    save_data: dict = Field(..., description="与客户端存档 Schema v1 一致")
    version: int | None = None
    # 客户端上次看到的版本号；不匹配说明别人改过，要 409 而不是静默覆盖
    base_rev: int | None = None


def _require_device(x_device_id: str | None) -> str:
    if not x_device_id:
        raise HTTPException(status_code=400, detail="缺少 X-Device-Id")
    cleaned = x_device_id.strip()
    if not (DEVICE_ID_MIN <= len(cleaned) <= DEVICE_ID_MAX):
        raise HTTPException(status_code=400, detail="X-Device-Id 长度不合法")
    return cleaned


def _check_slot(slot: int) -> int:
    if slot < 0 or slot > MAX_SLOT_INDEX:
        raise HTTPException(status_code=422, detail=f"槽位必须在 0..{MAX_SLOT_INDEX} 之间")
    return slot


def _user_for_device(db: Session, device_id: str) -> User:
    username = ANONYMOUS_PREFIX + device_id
    user = db.query(User).filter(User.username == username).one_or_none()
    if user is None:
        # 密码占位：匿名设备没有密码，账号体系接上时由用户主动绑定
        user = User(username=username, password_hash="!")
        db.add(user)
        db.commit()
        db.refresh(user)
    return user


@router.get("/saves/{slot}")
def read_save(
    slot: int,
    x_device_id: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> dict:
    """读云端存档。没有就返回 404，客户端据此保留本地存档。"""
    _check_slot(slot)
    device_id = _require_device(x_device_id)
    user = _user_for_device(db, device_id)

    row = (
        db.query(SaveData)
        .filter(SaveData.user_id == user.id, SaveData.slot == slot)
        .one_or_none()
    )
    if row is None:
        raise HTTPException(status_code=404, detail="云端没有这个槽位的存档")

    return {
        "slot": slot,
        "updated_at": row.updated_at.isoformat() if isinstance(row.updated_at, datetime) else str(row.updated_at),
        "rev": _rev_of(row),
        "save_data": row.save_data,
    }


@router.put("/saves/{slot}")
def write_save(
    slot: int,
    payload: SavePayload,
    x_device_id: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> dict:
    """写云端存档。同一 (设备, 槽位) 覆盖写，不堆历史版本。"""
    _check_slot(slot)
    device_id = _require_device(x_device_id)
    user = _user_for_device(db, device_id)

    row = (
        db.query(SaveData)
        .filter(SaveData.user_id == user.id, SaveData.slot == slot)
        .one_or_none()
    )
    current_rev = _rev_of(row) if row is not None else 0
    if payload.base_rev is not None and payload.base_rev != current_rev:
        raise HTTPException(status_code=409, detail={
            "message": "存档已被别处修改",
            "rev": current_rev,
            "save_data": row.save_data if row is not None else None,
        })

    data = dict(payload.save_data)
    data["_rev"] = current_rev + 1
    if row is None:
        row = SaveData(user_id=user.id, slot=slot, save_data=data)
        db.add(row)
    else:
        row.save_data = data

    db.commit()
    db.refresh(row)

    return {
        "slot": slot,
        "updated_at": row.updated_at.isoformat() if isinstance(row.updated_at, datetime) else str(row.updated_at),
        "rev": data["_rev"],
        "bytes": len(str(data)),
    }

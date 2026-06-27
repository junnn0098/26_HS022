from datetime import datetime

from fastapi import APIRouter

router = APIRouter()


@router.get("/")
def root():
    return {
        "project": "Hanium CSI Safety System",
        "status": "running",
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    }


@router.get("/health")
def health():
    return {"ok": True}

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from routers import alarm, device, state, status, websocket
from services.fcm_service import init_firebase


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_firebase()
    yield


app = FastAPI(
    title="Hanium CSI Safety API",
    description="WiFi CSI 기반 어르신 안전 모니터링 서버",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(status.router)
app.include_router(state.router)
app.include_router(websocket.router)
app.include_router(device.router)
app.include_router(alarm.router)

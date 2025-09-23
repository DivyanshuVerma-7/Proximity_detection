import asyncio
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi import WebSocket
from backend.yolo_module.inference import background_loop, LATEST_RESULT, RESULT_LOCK
from starlette.websockets import WebSocketDisconnect

app = FastAPI(title="Proximity Detection API")

# Allow CORS for all (so frontend on mobile can access it)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.websocket("/ws/results")
async def websocket_results(ws: WebSocket):
    await ws.accept()
    try:
        while True:
            async with RESULT_LOCK:
                await ws.send_json(LATEST_RESULT)
            await asyncio.sleep(0.2)
    except WebSocketDisconnect:
        print("WebSocket client disconnected")
    except Exception as e:
        print("WS error:", e)

@app.on_event("startup")
async def startup_event():
    # Start background video processing loop
    asyncio.create_task(background_loop())

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/results")
async def get_results():
    """
    Always return the latest processed frame summary.
    Background loop updates it continuously.
    """
    async with RESULT_LOCK:
        return JSONResponse(content=LATEST_RESULT)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("backend.app:app", host="0.0.0.0", port=8000, reload=True)

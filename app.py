# app.py
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from pathlib import Path
from services.llm import process_message

app = FastAPI()


@app.get("/")
async def serve_frontend():
    html_file = Path("index.html")
    if html_file.exists():
        return HTMLResponse(content=html_file.read_text())
    else:
        return HTMLResponse(
            content="<h1>Error: index.html not found</h1>", status_code=404
        )


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """Single WebSocket for all LLM and tool interactions"""
    await websocket.accept()
    print("✓ Client connected")

    try:
        while True:
            data = await websocket.receive_text()
            import json
            message_data = json.loads(data)
            user_message = message_data.get("message", "")

            print(f"📩 Received: {user_message}")

            # Pass to LLM service (may include tool calls)
            await process_message(user_message, websocket)

    except WebSocketDisconnect:
        print("✗ Client disconnected")
    except Exception as e:
        print(f"❌ Error: {e}")
        await websocket.close()


@app.get("/health")
async def health_check():
    return {"status": "ok"}

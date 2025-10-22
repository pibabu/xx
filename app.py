from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from pathlib import Path
from services.llm import process_message

app = FastAPI()


@app.get("/")
async def serve_frontend():
    """
    Serves index.html at root URL
    All frontend code (HTML, CSS, JS) in one file
    """
    html_file = Path("index.html")

    if html_file.exists():
        return HTMLResponse(content=html_file.read_text())
    else:
        return HTMLResponse(
            content="<h1>Error: index.html not found</h1>", status_code=404
        )


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
   
    await websocket.accept()
    print("✓ Client connected")

    try:
        while True:
            # Receive message from frontend
            data = await websocket.receive_text()
            import json

            message_data = json.loads(data)
            user_message = message_data.get("message", "")

            print(f"📩 Received: {user_message}")

            # Process message through AI service (streaming)
            await process_message(user_message, websocket)

    except WebSocketDisconnect:
        print("✗ Client disconnected")
    except Exception as e:
        print(f"❌ Error: {e}")
    finally:
        # Always cleanup conversation history

        cleanup_conversation(websocket) #not defined
        try:
            await websocket.close()
        except:
            pass  # Already closed


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "ok"}
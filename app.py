from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from pathlib import Path
from services.llm import process_message
import uuid


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
    await websocket.accept()
    
    # Create unique session ID for this connection
    session_id = str(uuid.uuid4())
    
    try:
        while True:
            data = await websocket.receive_text()
            message_data = json.loads(data)
            user_message = message_data.get("message", "")
            
            # Pass session_id to track conversation
            await process_message(user_message, websocket, session_id)
    
    except WebSocketDisconnect:
        # Clean up this session's history when user disconnects
        from services.llm import conversation_manager
        conversation_manager.clear_session(session_id)

@app.get("/health")
async def health_check():
    return {"status": "ok"}

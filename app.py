from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.responses import HTMLResponse
from pathlib import Path
import json
import subprocess
from typing import Optional
from services.llm_chat import process_message
from services.conversation_manager import ConversationManager, BASH_TOOL_SCHEMA
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://ey-ios.com"],  
    allow_credentials=True,
    allow_methods=["*"], 
    allow_headers=["*"],  
)


@app.get("/")
async def get():
    with open('index.html', 'r', encoding='utf-8') as f:
        html_content = f.read()
    return HTMLResponse(content=html_content)



def container_exists_by_hash(user_hash: str) -> bool:
    """Check if container with user_hash label exists."""
    result = subprocess.run(
        ["docker", "ps", "--filter", f"label=user_hash={user_hash}", 
         "--format", "{{.Names}}"],
        capture_output=True,
        text=True
    )
    return bool(result.stdout.strip())


@app.websocket("/ws/{user_hash}")
async def websocket_endpoint(websocket: WebSocket, user_hash: str):
    print(f"DEBUG: WebSocket connection attempt for user_hash={user_hash}")
    
    if not container_exists_by_hash(user_hash):
        print(f"ERROR: No container found for user_hash={user_hash}")
        await websocket.close(code=1008, reason="Container not found")
        return
    
    await websocket.accept()
    print(f"✓ Client connected: {user_hash}")
    
    manager = ConversationManager(user_hash=user_hash)
    
    try:
        while True:
            data = await websocket.receive_text()
            print(f"DEBUG: Received data: {data[:100]}")  # Log what we receive
            
            # Validate JSON
            try:
                message_data = json.loads(data)
            except json.JSONDecodeError as e:
                print(f"✗ Invalid JSON: {e}")
                await websocket.send_json({
                    "type": "error",
                    "message": f"Invalid JSON format. Please send: {{'message': 'your text'}}"
                })
                continue  # Don't close, keep connection open
            
            user_message = message_data.get("message", "")
            if not user_message:
                await websocket.send_json({
                    "type": "error",
                    "message": "Missing 'message' field"
                })
                continue
            
            print(f"DEBUG: Processing message: {user_message}")
            manager.add_user_message(user_message)
            await process_message(manager, websocket)
    
    except WebSocketDisconnect:
        print("✗ Client disconnected")
    except Exception as e:
        print(f"✗ Unexpected error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        print("DEBUG: Saving conversation...")
        try:
            manager.save()
            print("DEBUG: Conversation saved successfully")
        except Exception as e:
            print(f"DEBUG: Save failed: {e}")
        
        try:
            await websocket.close()
        except:
            pass


@app.post("/api/llm/quick")   ####subprocess



@app.post("/api/conversation/export")
async def export_conversation(request: dict):
    """Return current conversation state for bash to save."""
    user_hash = request["user_hash"]
    conv = ConversationManager(user_hash)
    
    return conv.get_conversation_data()

        
@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "ok"}


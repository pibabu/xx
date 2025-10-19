import asyncio
import os
import json
import traceback
import logging
from typing import Optional, Dict, List
from dotenv import load_dotenv
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from openai import AsyncOpenAI
import docker
from docker.errors import DockerException, NotFound

# ═══════════════════════════════════════════════════════
# SETUP
# ═══════════════════════════════════════════════════════
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)
load_dotenv()
app = FastAPI()

# ═══════════════════════════════════════════════════════
# INITIALIZATION
# ═══════════════════════════════════════════════════════
try:
    client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))
    logger.info("✓ OpenAI client initialized")
except Exception as e:
    logger.error(f"❌ OpenAI initialization failed: {e}")
    client = None

try:
    docker_client = docker.from_env()
    docker_client.ping()
    logger.info("✓ Docker client initialized")
except DockerException as e:
    logger.error(f"❌ Docker connection failed: {e}")
    docker_client = None

# ═══════════════════════════════════════════════════════
# SESSION & AI CONFIG
# ═══════════════════════════════════════════════════════
active_sessions: Dict[str, List[dict]] = {}
TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "start_container",
            "description": "Starts a Docker container workspace for a user.",
            "parameters": {
                "type": "object",
                "properties": {
                    "username": {
                        "type": "string",
                        "description": "A unique username (e.g., 'john_doe').",
                    },
                    "name": {"type": "string", "description": "User's full name."},
                },
                "required": ["username", "name"],
            },
        },
    }
]
SYSTEM_PROMPT = """You are an assistant that manages user workspaces in Docker containers.
1. Greet the user and ask for their name to create a workspace.
2. Use the start_container function with their name and a generated username.
3. Confirm to the user that their workspace is ready."""


def initialize_session(session_id: str):
    active_sessions[session_id] = [{"role": "system", "content": SYSTEM_PROMPT}]
    logger.info(f"Initialized session: {session_id}")


# ═══════════════════════════════════════════════════════
# DOCKER MANAGEMENT
# ═══════════════════════════════════════════════════════
def start_user_container(username: str, name: str) -> Optional[str]:
    if not docker_client:
        logger.error("Docker client not available")
        return None

    container_name = f"user_{username}_container"
    try:
        container = docker_client.containers.get(container_name)
        if container.status != "running":
            container.start()
        logger.info(f"Container {container_name} already exists and is running.")
        return container.id
    except NotFound:
        logger.info(f"Container {container_name} not found. Creating...")
        try:
            user_volume = f"user_{username}_volume"
            docker_client.volumes.create(user_volume)
            container = docker_client.containers.run(
                "ubuntu:22.04",
                name=container_name,
                detach=True,
                tty=True,
                volumes={user_volume: {"bind": "/home/user", "mode": "rw"}},
                labels={"user": username, "name": name},
                command="tail -f /dev/null",
            )
            welcome_cmd = f'echo "Welcome, {name}! Your workspace is ready." > /home/user/README.md'
            container.exec_run(f"sh -c '{welcome_cmd}'")
            logger.info(
                f"✓ Created container {container_name} (ID: {container.short_id})"
            )
            return container.id
        except Exception as e:
            logger.error(
                f"❌ Failed to create container: {e}\n{traceback.format_exc()}"
            )
            return None


# ═══════════════════════════════════════════════════════
# WEBSOCKET & AI LOGIC
# ═══════════════════════════════════════════════════════
async def handle_tool_call(tool_call, websocket):
    function_name = tool_call.function.name
    args = json.loads(tool_call.function.arguments)
    logger.info(f"🔧 Tool call: {function_name}({args})")

    if function_name == "start_container":
        username = args.get("username", "").lower().replace(" ", "_")
        name = args.get("name")
        container_id = start_user_container(username, name)
        result = {"success": bool(container_id), "container_id": container_id}
        await websocket.send_json({"type": "container_status", "data": result})
        return json.dumps(result)
    return json.dumps({"error": "Unknown function"})


async def process_message(user_message: str, websocket, session_id: str):
    if not client:
        await websocket.send_json(
            {"type": "error", "message": "AI service not available"}
        )
        return

    messages = active_sessions.get(session_id, [])
    messages.append({"role": "user", "content": user_message})
    await websocket.send_json({"type": "start"})

    try:
        response = await client.chat.completions.create(
            model="gpt-4o-mini", messages=messages, tools=TOOLS, tool_choice="auto"
        )
        assistant_message = response.choices[0].message
        messages.append(assistant_message)

        if assistant_message.tool_calls:
            for tool_call in assistant_message.tool_calls:
                response_content = await handle_tool_call(tool_call, websocket)
                messages.append(
                    {
                        "role": "tool",
                        "tool_call_id": tool_call.id,
                        "content": response_content,
                    }
                )

            stream = await client.chat.completions.create(
                model="gpt-4o-mini", messages=messages, stream=True
            )
            full_response = ""
            async for chunk in stream:
                content = chunk.choices[0].delta.content or ""
                full_response += content
                await websocket.send_json({"type": "token", "content": content})
            messages.append({"role": "assistant", "content": full_response})
        elif assistant_message.content:
            await websocket.send_json(
                {"type": "token", "content": assistant_message.content}
            )

        await websocket.send_json({"type": "end"})
    except Exception as e:
        logger.error(f"❌ WebSocket error: {e}\n{traceback.format_exc()}")
        await websocket.send_json({"type": "error", "message": str(e)})


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    session_id = str(id(websocket))
    initialize_session(session_id)
    logger.info(f"Client connected: {session_id}")
    try:
        while True:
            user_message = json.loads(await websocket.receive_text()).get("message", "")
            await process_message(user_message, websocket, session_id)
    except WebSocketDisconnect:
        logger.info(f"Client disconnected: {session_id}")
    finally:
        if session_id in active_sessions:
            del active_sessions[session_id]


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=80)

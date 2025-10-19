import asyncio
import os
import json
import traceback
import logging
from datetime import datetime
from typing import Optional, Dict, List
from dotenv import load_dotenv
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from openai import AsyncOpenAI
import docker
from docker.errors import DockerException, NotFound

# ═══════════════════════════════════════════════════════
# LOGGING SETUP - Critical for AWS debugging
# ═══════════════════════════════════════════════════════
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[
        logging.StreamHandler(),  # Console output
        logging.FileHandler("app.log"),  # File for persistence
    ],
)
logger = logging.getLogger(__name__)

load_dotenv()

app = FastAPI()

# ═══════════════════════════════════════════════════════
# INITIALIZATION WITH ERROR HANDLING
# ═══════════════════════════════════════════════════════

try:
    client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))
    logger.info("✓ OpenAI client initialized")
except Exception as e:
    logger.error(f"❌ OpenAI initialization failed: {e}")
    client = None

try:
    docker_client = docker.from_env()
    docker_client.ping()  # Test connection
    logger.info("✓ Docker client initialized and connected")
except DockerException as e:
    logger.error(f"❌ Docker connection failed: {e}")
    logger.error(traceback.format_exc())
    docker_client = None
except Exception as e:
    logger.error(f"❌ Unexpected Docker error: {e}")
    logger.error(traceback.format_exc())
    docker_client = None


# ═══════════════════════════════════════════════════════
# SESSION MANAGEMENT - Track conversation history per user
# ═══════════════════════════════════════════════════════

# Store conversation history per WebSocket connection
active_sessions: Dict[str, List[dict]] = {}


def get_session_id(websocket: WebSocket) -> str:
    """Generate unique session ID from websocket"""
    return f"session_{id(websocket)}"


def initialize_session(session_id: str):
    """Initialize conversation history for a new session"""
    active_sessions[session_id] = [
        {
            "role": "system",
            "content": """You are a helpful assistant that manages user workspaces in Docker containers.

When a new user connects, you should:
1. Greet them warmly
2. Ask for their information: name, age, job/occupation, and interests
3. Once you have ALL this information, use the start_container function to create their workspace
4. Confirm that their workspace is ready

Be conversational and friendly. Collect the information naturally.""",
        }
    ]
    logger.info(f"Initialized session: {session_id}")


# ═══════════════════════════════════════════════════════
# DOCKER CONTAINER MANAGEMENT
# ═══════════════════════════════════════════════════════


def ensure_shared_volume():
    """Creates the shared volume if it doesn't exist"""
    if not docker_client:
        logger.error("Docker client not available")
        return False

    try:
        docker_client.volumes.get("shared_volume")
        logger.info("✓ Shared volume exists")
        return True
    except NotFound:
        try:
            docker_client.volumes.create("shared_volume")
            logger.info("✓ Created shared_volume")
            return True
        except Exception as e:
            logger.error(f"Failed to create shared volume: {e}")
            return False
    except Exception as e:
        logger.error(f"Error checking shared volume: {e}")
        return False


def create_user_volume(username: str) -> Optional[str]:
    """Creates a private volume for a specific user"""
    if not docker_client:
        logger.error("Docker client not available")
        return None

    volume_name = f"user_{username}_volume"
    try:
        docker_client.volumes.get(volume_name)
        logger.info(f"✓ Volume {volume_name} already exists")
        return volume_name
    except NotFound:
        try:
            docker_client.volumes.create(volume_name)
            logger.info(f"✓ Created {volume_name}")
            return volume_name
        except Exception as e:
            logger.error(f"Failed to create volume {volume_name}: {e}")
            return None
    except Exception as e:
        logger.error(f"Error checking volume {volume_name}: {e}")
        return None


def register_user_in_shared_volume(username: str, metadata: dict):
    """Adds user to registry file in shared volume"""
    if not docker_client:
        logger.error("Docker client not available")
        return False

    registry_entry = {
        "username": username,
        "registered_at": datetime.now().isoformat(),
        "metadata": metadata,
    }

    # Escape single quotes in JSON for shell command
    json_str = json.dumps(registry_entry).replace("'", "'\\''")
    command = f"sh -c 'echo '\\''{ json_str}'\\'' >> /shared/registry_users.jsonl'"

    try:
        result = docker_client.containers.run(
            "alpine:latest",
            command=command,
            volumes={"shared_volume": {"bind": "/shared", "mode": "rw"}},
            remove=True,
        )
        logger.info(f"✓ Registered {username} in shared volume")
        return True
    except Exception as e:
        logger.error(f"❌ Failed to register user: {e}")
        logger.error(traceback.format_exc())
        return False


def start_user_container(username: str, metadata: dict) -> Optional[str]:
    """Starts a user's container with private and shared volumes"""
    if not docker_client:
        logger.error("❌ Docker client not available")
        return None

    container_name = f"user_{username}_container"

    # Check if container already exists
    try:
        existing = docker_client.containers.get(container_name)
        logger.info(
            f"⚠ Container {container_name} already exists (status: {existing.status})"
        )
        if existing.status != "running":
            existing.start()
            logger.info(f"✓ Started existing container")
        return existing.id
    except NotFound:
        pass  # Container doesn't exist, we'll create it
    except Exception as e:
        logger.error(f"Error checking existing container: {e}")

    # Ensure volumes exist
    if not ensure_shared_volume():
        return None

    user_volume = create_user_volume(username)
    if not user_volume:
        return None

    # Register user in shared volume
    register_user_in_shared_volume(username, metadata)

    # Start the container
    try:
        logger.info(f"Starting container for {username}...")
        container = docker_client.containers.run(
            "ubuntu:22.04",
            name=container_name,
            detach=True,
            tty=True,
            stdin_open=True,
            volumes={
                user_volume: {"bind": "/home/user", "mode": "rw"},
                "shared_volume": {"bind": "/shared", "mode": "ro"},
            },
            labels={
                "user": username,
                "name": metadata.get("name", ""),
                "age": str(metadata.get("age", "")),
                "job": metadata.get("job", ""),
                "interests": metadata.get("interests", ""),
            },
            command="tail -f /dev/null",
        )

        logger.info(f"✓ Started container {container_name} (ID: {container.short_id})")

        # Create README in user's home directory
        try:
            exec_result = container.exec_run(
                f"sh -c 'echo \"Welcome {metadata.get('name', username)}!\\n\\nYour workspace is ready.\" > /home/user/README.md'"
            )
            logger.info(f"✓ Created README.md for {username}")
        except Exception as e:
            logger.warning(f"Failed to create README: {e}")

        return container.id

    except Exception as e:
        logger.error(f"❌ Failed to start container: {e}")
        logger.error(traceback.format_exc())
        return None


# ═══════════════════════════════════════════════════════
# AI SERVICE WITH TOOL CALLING
# ═══════════════════════════════════════════════════════

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "start_container",
            "description": "Start a Docker container workspace for a user with their personal information",
            "parameters": {
                "type": "object",
                "properties": {
                    "username": {
                        "type": "string",
                        "description": "Username (lowercase, no spaces, e.g., 'john_doe')",
                    },
                    "name": {"type": "string", "description": "User's full name"},
                    "age": {"type": "integer", "description": "User's age"},
                    "job": {"type": "string", "description": "User's job/occupation"},
                    "interests": {
                        "type": "string",
                        "description": "User's interests (comma-separated)",
                    },
                },
                "required": ["username", "name", "age"],
            },
        },
    }
]


async def handle_tool_call(tool_call, websocket):
    """Execute tool calls from the LLM"""
    function_name = tool_call.function.name

    try:
        arguments = json.loads(tool_call.function.arguments)
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse tool arguments: {e}")
        return json.dumps({"success": False, "error": "Invalid arguments"})

    logger.info(f"🔧 Tool call: {function_name}")
    logger.info(f"📋 Arguments: {arguments}")

    if function_name == "start_container":
        username = arguments.get("username", "").lower().replace(" ", "_")
        metadata = {
            "name": arguments.get("name"),
            "age": arguments.get("age"),
            "job": arguments.get("job", ""),
            "interests": arguments.get("interests", ""),
        }

        # Start the container
        container_id = start_user_container(username, metadata)

        if container_id:
            result = {
                "success": True,
                "container_id": container_id,
                "username": username,
                "message": f"Container workspace created successfully for {username}",
            }
            logger.info(f"✓ Container started: {result}")
        else:
            result = {
                "success": False,
                "message": "Failed to start container. Check Docker connection.",
            }
            logger.error(f"❌ Container start failed")

        # Send status update to frontend
        try:
            await websocket.send_json({"type": "container_status", "data": result})
        except Exception as e:
            logger.error(f"Failed to send container status: {e}")

        return json.dumps(result)

    return json.dumps({"error": "Unknown function"})


async def process_message(user_message: str, websocket, session_id: str):
    """Process message with AI and handle tool calls"""

    if not client:
        await websocket.send_json(
            {"type": "error", "message": "AI service not initialized"}
        )
        return

    # Get conversation history for this session
    messages = active_sessions.get(session_id)
    if not messages:
        initialize_session(session_id)
        messages = active_sessions[session_id]

    # Add user message to history
    messages.append({"role": "user", "content": user_message})

    await websocket.send_json({"type": "start"})

    try:
        # Call OpenAI with tools - NON-STREAMING first to detect tool calls
        logger.info(f"Sending request to OpenAI (messages: {len(messages)})")
        response = await client.chat.completions.create(
            model="gpt-4o-mini",
            messages=messages,
            tools=TOOLS,  # This is critical!
            tool_choice="auto",
            temperature=0.7,
        )

        assistant_message = response.choices[0].message
        logger.info(
            f"OpenAI response - finish_reason: {response.choices[0].finish_reason}"
        )

        # Check for tool calls
        if assistant_message.tool_calls:
            logger.info(f"🔧 Detected {len(assistant_message.tool_calls)} tool call(s)")

            # Add assistant message with tool calls to history
            messages.append(
                {
                    "role": "assistant",
                    "content": assistant_message.content,
                    "tool_calls": [
                        {
                            "id": tc.id,
                            "type": "function",
                            "function": {
                                "name": tc.function.name,
                                "arguments": tc.function.arguments,
                            },
                        }
                        for tc in assistant_message.tool_calls
                    ],
                }
            )

            # Execute each tool call
            for tool_call in assistant_message.tool_calls:
                function_response = await handle_tool_call(tool_call, websocket)

                # Add tool response to messages
                messages.append(
                    {
                        "role": "tool",
                        "tool_call_id": tool_call.id,
                        "content": function_response,
                    }
                )

            # Get final response after tool execution (STREAMING)
            logger.info("Getting final response after tool execution...")
            stream = await client.chat.completions.create(
                model="gpt-4o-mini", messages=messages, stream=True, temperature=0.7
            )

            full_response = ""
            async for chunk in stream:
                if chunk.choices[0].delta.content:
                    content = chunk.choices[0].delta.content
                    full_response += content
                    await websocket.send_json({"type": "token", "content": content})

            # Add final response to history
            messages.append({"role": "assistant", "content": full_response})

        else:
            # No tool calls, stream the response directly
            logger.info("No tool calls detected, streaming response...")

            if assistant_message.content:
                # If we have content from the non-streaming call, send it
                await websocket.send_json(
                    {"type": "token", "content": assistant_message.content}
                )
                messages.append(
                    {"role": "assistant", "content": assistant_message.content}
                )
            else:
                # Otherwise make a streaming call
                stream = await client.chat.completions.create(
                    model="gpt-4o-mini", messages=messages, stream=True, temperature=0.7
                )

                full_response = ""
                async for chunk in stream:
                    if chunk.choices[0].delta.content:
                        content = chunk.choices[0].delta.content
                        full_response += content
                        await websocket.send_json({"type": "token", "content": content})

                messages.append({"role": "assistant", "content": full_response})

        await websocket.send_json({"type": "end"})
        logger.info("✓ Message processed successfully")

    except Exception as e:
        logger.error(f"❌ Error in process_message: {e}")
        logger.error(traceback.format_exc())
        await websocket.send_json(
            {"type": "error", "message": f"AI service error: {str(e)}"}
        )


# ═══════════════════════════════════════════════════════
# FASTAPI ROUTES
# ═══════════════════════════════════════════════════════


@app.on_event("startup")
async def startup_event():
    """Log startup information"""
    logger.info("=" * 50)
    logger.info("FastAPI Application Starting")
    logger.info(f"OpenAI Client: {'✓ Ready' if client else '❌ Not Available'}")
    logger.info(f"Docker Client: {'✓ Ready' if docker_client else '❌ Not Available'}")
    logger.info("=" * 50)


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for real-time chat"""
    session_id = None
    try:
        await websocket.accept()
        session_id = get_session_id(websocket)
        initialize_session(session_id)
        logger.info(f"✓ Client connected - {session_id}")

        while True:
            data = await websocket.receive_text()
            message_data = json.loads(data)
            user_message = message_data.get("message", "")
            logger.info(f"📩 [{session_id}] Received: {user_message}")

            await process_message(user_message, websocket, session_id)

    except WebSocketDisconnect:
        logger.info(f"✗ Client disconnected - {session_id}")
        if session_id and session_id in active_sessions:
            del active_sessions[session_id]
    except Exception as e:
        logger.error(f"❌ WebSocket error: {e}")
        logger.error(traceback.format_exc())
        try:
            await websocket.close()
        except:
            pass
        if session_id and session_id in active_sessions:
            del active_sessions[session_id]


@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "status": "running",
        "message": "FastAPI Docker Container Manager",
        "endpoints": {
            "websocket": "/ws",
            "health": "/health",
            "containers": "/containers",
            "volumes": "/volumes",
        },
    }


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    docker_status = "connected" if docker_client else "disconnected"
    openai_status = "configured" if client else "not_configured"

    return {
        "status": "ok",
        "docker": docker_status,
        "openai": openai_status,
        "active_sessions": len(active_sessions),
    }


@app.get("/containers")
async def list_containers():
    """List all user containers (debug endpoint)"""
    if not docker_client:
        return {"error": "Docker not available"}

    try:
        containers = docker_client.containers.list(all=True, filters={"name": "user_"})

        return {
            "count": len(containers),
            "containers": [
                {
                    "name": c.name,
                    "status": c.status,
                    "id": c.short_id,
                    "labels": c.labels,
                }
                for c in containers
            ],
        }
    except Exception as e:
        logger.error(f"Error listing containers: {e}")
        return {"error": str(e)}


@app.get("/volumes")
async def list_volumes():
    """List all volumes (debug endpoint)"""
    if not docker_client:
        return {"error": "Docker not available"}

    try:
        volumes = docker_client.volumes.list()
        return {"count": len(volumes), "volumes": [v.name for v in volumes]}
    except Exception as e:
        logger.error(f"Error listing volumes: {e}")
        return {"error": str(e)}


if __name__ == "__main__":
    import uvicorn

    logger.info("Starting server...")
    uvicorn.run(app, host="0.0.0.0", port=80, log_level="info")

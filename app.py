# ai_handler.py
import asyncio
import os
import json
import subprocess
from dotenv import load_dotenv
from openai import AsyncOpenAI

load_dotenv()
client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))


async def process_message(user_message: str, websocket):
    """
    Your existing function - NO CHANGES needed here!
    """
    await websocket.send_json({"type": "start"})
    await _openai_streaming_response(user_message, websocket)
    await websocket.send_json({"type": "end"})


# 👇 REPLACE this entire function
async def _openai_streaming_response(user_message: str, websocket):
    """
    Enhanced version with tool calling

    What changed:
    - Added 'tools' parameter to API call
    - Handle tool_calls in streaming response
    - Execute tools when AI requests them
    - Send results back to AI for final answer
    """
    try:
        # STEP 1: Define available tools
        # Why: Tell AI what actions it can perform
        tools = [
            {
                "type": "function",
                "function": {
                    "name": "create_container",
                    "description": "Create a new Docker container",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "name": {"type": "string", "description": "Container name"},
                            "image": {
                                "type": "string",
                                "description": "Docker image (e.g., 'nginx:latest')",
                            },
                            "max_lines": {
                                "type": "integer",
                                "description": "Log lines to capture",
                                "default": 160,
                            },
                        },
                        "required": ["name", "image"],
                    },
                },
            }
        ]

        # STEP 2: Initial conversation with AI
        messages = [
            {
                "role": "system",
                "content": "You are a helpful Docker assistant. Use tools when needed.",
            },
            {"role": "user", "content": user_message},
        ]

        # STEP 3: First API call - AI decides if it needs tools
        stream = await client.chat.completions.create(
            model="gpt-4o-mini",
            messages=messages,
            tools=tools,  # 👈 This enables tool calling
            stream=True,
            temperature=0.7,
        )

        # STEP 4: Collect streaming response
        tool_calls = []  # Will store tool requests if any
        current_tool_call = None
        response_content = ""

        async for chunk in stream:
            delta = chunk.choices[0].delta

            # Stream regular text to user
            if delta.content:
                response_content += delta.content
                await websocket.send_json({"type": "token", "content": delta.content})

            # AI wants to use a tool!
            if delta.tool_calls:
                for tc_delta in delta.tool_calls:
                    # Initialize new tool call
                    if tc_delta.index is not None:
                        while len(tool_calls) <= tc_delta.index:
                            tool_calls.append(
                                {"id": "", "function": {"name": "", "arguments": ""}}
                            )
                        current_tool_call = tool_calls[tc_delta.index]

                    # Accumulate tool call data (comes in chunks like text)
                    if tc_delta.id:
                        current_tool_call["id"] = tc_delta.id
                    if tc_delta.function.name:
                        current_tool_call["function"]["name"] = tc_delta.function.name
                    if tc_delta.function.arguments:
                        current_tool_call["function"]["arguments"] += (
                            tc_delta.function.arguments
                        )

        # STEP 5: Execute tools if AI requested them
        if tool_calls:
            for tool_call in tool_calls:
                tool_name = tool_call["function"]["name"]

                # Notify user we're using a tool
                await websocket.send_json({"type": "tool_start", "tool": tool_name})

                # Parse arguments and execute
                args = json.loads(tool_call["function"]["arguments"])
                result = await execute_tool(tool_name, args)

                # Show result to user
                await websocket.send_json({"type": "tool_result", "content": result})

                # STEP 6: Update conversation history
                # Add AI's tool request
                messages.append(
                    {
                        "role": "assistant",
                        "tool_calls": [
                            {
                                "id": tool_call["id"],
                                "type": "function",
                                "function": {
                                    "name": tool_name,
                                    "arguments": tool_call["function"]["arguments"],
                                },
                            }
                        ],
                    }
                )

                # Add tool result
                messages.append(
                    {"role": "tool", "tool_call_id": tool_call["id"], "content": result}
                )

            # STEP 7: Ask AI to formulate final answer
            # Now AI has tool results and can give a proper response
            final_stream = await client.chat.completions.create(
                model="gpt-4o-mini", messages=messages, stream=True
            )

            async for chunk in final_stream:
                if chunk.choices[0].delta.content:
                    await websocket.send_json(
                        {"type": "token", "content": chunk.choices[0].delta.content}
                    )

    except Exception as e:
        await websocket.send_json({"type": "error", "message": f"Error: {str(e)}"})
        print(f"OpenAI API Error: {e}")


# 👇 ADD these two new functions at the end of the file
async def execute_tool(tool_name: str, args: dict) -> str:
    """
    Router function - calls the right tool based on name

    Why separate: Easy to add more tools later
    """
    if tool_name == "create_container":
        return await create_container(
            name=args["name"], image=args["image"], max_lines=args.get("max_lines", 160)
        )

    return f"Unknown tool: {tool_name}"


async def create_container(name: str, image: str, max_lines: int = 160) -> str:
    """
    Actually create the Docker container

    What it does:
    1. Runs 'docker run -d --name X image' command
    2. Waits 2 seconds for container to start
    3. Captures last N lines of logs
    4. Returns formatted result

    Why async: Don't block other users while waiting for Docker
    """
    try:
        # Create container (detached mode)
        subprocess.run(
            ["docker", "run", "-d", "--name", name, image],
            check=True,
            capture_output=True,
            text=True,
        )

        # Give container time to start and generate logs
        await asyncio.sleep(2)

        # Fetch logs
        logs = subprocess.run(
            ["docker", "logs", "--tail", str(max_lines), name],
            capture_output=True,
            text=True,
        )

        return f"✅ Container '{name}' created from {image}\n\nLogs (last {max_lines} lines):\n{logs.stdout}"

    except subprocess.CalledProcessError as e:
        return f"❌ Failed to create container: {e.stderr}"

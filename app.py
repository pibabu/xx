async def _openai_streaming_response(user_message: str, websocket):
    """
    Enhanced with tool calling support

    Tool calling flow:
    1. AI decides to use a tool (e.g., "create_container")
    2. We execute the tool with provided parameters
    3. Send results back to AI
    4. AI formulates final response to user
    """
    try:
        # Define available tools
        tools = [
            {
                "type": "function",
                "function": {
                    "name": "create_container",
                    "description": "Create a new Docker container with specified configuration",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "name": {
                                "type": "string",
                                "description": "Container name (e.g., 'my-app')",
                            },
                            "image": {
                                "type": "string",
                                "description": "Docker image with tag (e.g., 'nginx:latest')",
                            },
                            "max_lines": {
                                "type": "integer",
                                "description": "Maximum log lines to capture",
                                "default": 160,
                            },
                        },
                        "required": ["name", "image"],
                    },
                },
            }
        ]

        messages = [
            {
                "role": "system",
                "content": "You are a helpful Docker assistant. Use tools when needed.",
            },
            {"role": "user", "content": user_message},
        ]

        # First call - AI may request tool use
        stream = await client.chat.completions.create(
            model="gpt-4o-mini",
            messages=messages,
            tools=tools,  # Tell AI about available tools
            stream=True,
            temperature=0.7,
        )

        tool_calls = []
        current_tool_call = None

        async for chunk in stream:
            delta = chunk.choices[0].delta

            # Handle regular text response
            if delta.content:
                await websocket.send_json({"type": "token", "content": delta.content})

            # Handle tool call request
            if delta.tool_calls:
                # AI wants to use a tool!
                for tc_delta in delta.tool_calls:
                    if tc_delta.index is not None:
                        # Start new tool call
                        if len(tool_calls) <= tc_delta.index:
                            tool_calls.append(
                                {"id": "", "function": {"name": "", "arguments": ""}}
                            )
                        current_tool_call = tool_calls[tc_delta.index]

                    # Accumulate tool call data
                    if tc_delta.id:
                        current_tool_call["id"] = tc_delta.id
                    if tc_delta.function.name:
                        current_tool_call["function"]["name"] = tc_delta.function.name
                    if tc_delta.function.arguments:
                        current_tool_call["function"]["arguments"] += (
                            tc_delta.function.arguments
                        )

        # Execute tool calls if any
        if tool_calls:
            await websocket.send_json(
                {"type": "tool_start", "tool": tool_calls[0]["function"]["name"]}
            )

            # Execute the tool
            import json

            args = json.loads(tool_calls[0]["function"]["arguments"])
            result = await execute_tool(tool_calls[0]["function"]["name"], args)

            await websocket.send_json({"type": "tool_result", "content": result})

            # Send tool result back to AI for final response
            messages.append(
                {
                    "role": "assistant",
                    "tool_calls": [
                        {
                            "id": tool_calls[0]["id"],
                            "type": "function",
                            "function": {
                                "name": tool_calls[0]["function"]["name"],
                                "arguments": tool_calls[0]["function"]["arguments"],
                            },
                        }
                    ],
                }
            )
            messages.append(
                {"role": "tool", "tool_call_id": tool_calls[0]["id"], "content": result}
            )

            # Get AI's final response after seeing tool results
            final_stream = await client.chat.completions.create(
                model="gpt-4o-mini", messages=messages, stream=True
            )

            async for chunk in final_stream:
                if chunk.choices[0].delta.content:
                    await websocket.send_json(
                        {"type": "token", "content": chunk.choices[0].delta.content}
                    )

    except Exception as e:
        await websocket.send_json(
            {"type": "error", "message": f"AI service error: {str(e)}"}
        )


async def execute_tool(tool_name: str, args: dict) -> str:
    """
    Execute the requested tool

    Why separate function:
    - Keeps tool logic isolated
    - Easy to add more tools later
    - Can add error handling per tool
    """
    if tool_name == "create_container":
        return await create_container(
            name=args["name"], image=args["image"], max_lines=args.get("max_lines", 160)
        )

    return f"Unknown tool: {tool_name}"


async def create_container(name: str, image: str, max_lines: int = 160) -> str:
    """
    Create Docker container and capture logs

    Args:
        name: Container name
        image: Docker image with tag (e.g., 'nginx:latest')
        max_lines: Maximum log lines to capture

    Returns:
        String with container info and logs
    """
    import subprocess

    try:
        # Create and start container
        subprocess.run(
            ["docker", "run", "-d", "--name", name, image],
            check=True,
            capture_output=True,
        )

        # Wait a moment for logs
        await asyncio.sleep(2)

        # Get logs (last N lines)
        logs = subprocess.run(
            ["docker", "logs", "--tail", str(max_lines), name],
            capture_output=True,
            text=True,
        )

        return f"✅ Container '{name}' created from {image}\n\nLogs:\n{logs.stdout}"

    except subprocess.CalledProcessError as e:
        return f"❌ Error: {e.stderr.decode()}"

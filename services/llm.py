import asyncio
import os
import json
from dotenv import load_dotenv
from openai import AsyncOpenAI
from services.conversation_manager import BASH_TOOL_SCHEMA, ConversationManager

load_dotenv()
client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))


async def process_message(cm, websocket):
    await websocket.send_json({"type": "start"})
    
    # Stream response from OpenAI (handles tools internally)
    assistant_response = await _stream_openai_response(cm, websocket)
    
    # Save assistant's final response to conversation history
    if assistant_response:
        cm.add_assistant_message(assistant_response)
    
    await websocket.send_json({"type": "end"})


async def _stream_openai_response(cm: ConversationManager, websocket, depth: int = 0):
    # FIX: Await the async method
    messages = await cm.get_messages()
    
    # Prevent infinite loops
    if depth > 3:
        error_msg = "Error: Too many tool calls (max 3)"
        await websocket.send_json({"type": "error", "message": error_msg})
        return error_msg
    
    try:
        # Call OpenAI with full conversation + tool schema
        stream = await client.chat.completions.create(
            model="gpt-4o-mini",
            messages=messages,
            tools=[BASH_TOOL_SCHEMA],
            stream=True,
            temperature=0.7,
        )
        
        # Accumulate streamed response
        full_content = ""
        tool_calls_buffer = {}
        
        # Process each chunk from OpenAI
        async for chunk in stream:
            if not chunk.choices:
                continue
                
            choice = chunk.choices[0]
            delta = choice.delta
            
            # CASE 1: LLM is calling a tool
            if delta.tool_calls:
                for tool_call_chunk in delta.tool_calls:
                    idx = tool_call_chunk.index
                    
                    # Initialize buffer for this tool call
                    if idx not in tool_calls_buffer:
                        tool_calls_buffer[idx] = {
                            "id": "",
                            "name": "",
                            "arguments": ""
                        }
                    
                    # Accumulate tool call data
                    if tool_call_chunk.id:
                        tool_calls_buffer[idx]["id"] = tool_call_chunk.id
                    if tool_call_chunk.function.name:
                        tool_calls_buffer[idx]["name"] = tool_call_chunk.function.name
                    if tool_call_chunk.function.arguments:
                        tool_calls_buffer[idx]["arguments"] += tool_call_chunk.function.arguments
            
            # CASE 2: LLM is responding with text
            elif delta.content:
                full_content += delta.content
                # Stream token to client in real-time
                await websocket.send_json({
                    "type": "token",
                    "content": delta.content
                })
        
        # After stream ends, process any tool calls
        if tool_calls_buffer:
            for tool_call in tool_calls_buffer.values():
                if tool_call["name"] == "bash_tool":
                    # Parse the JSON arguments
                    args = json.loads(tool_call["arguments"])
                    command = args["command"]
                    
                    # Notify client we're running a command
                    await websocket.send_json({
                        "type": "tool_call",
                        "tool": "bash",
                        "command": command
                    })
                    
                    # FIX: Await the async method
                    output = await cm.execute_bash_tool(command)
                    
                    # SAVE TO HISTORY: Tool call + result
                    cm.add_tool_call("bash_tool", args, tool_call["id"])
                    cm.add_tool_result(tool_call["id"], output)
                    
                    # Show result to client
                    await websocket.send_json({
                        "type": "tool_result",
                        "output": output
                    })
                    
                    # RECURSE: Send updated conversation back to LLM
                    return await _stream_openai_response(
                        cm, websocket, depth + 1
                    )
        
        # No tool calls → return final text response
        return full_content
    
    except Exception as e:
        error_msg = f"OpenAI API Error: {str(e)}"
        await websocket.send_json({"type": "error", "message": error_msg})
        print(error_msg)
        return error_msg
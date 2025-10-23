import asyncio
import os
import json
from dotenv import load_dotenv
from openai import AsyncOpenAI
from conversation_manager import BASH_TOOL_SCHEMA

load_dotenv()
client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))


async def process_message(cm, websocket):
    """
    Main entry point for processing a user message.
    
    What it does:
    1. Signals client that response is starting
    2. Gets full conversation history from ConversationManager
    3. Streams OpenAI response (which may include tool calls)
    4. Saves the final assistant response to history
    5. Signals client that response is complete
    
    Why we save assistant response here:
    - Tool calls are saved inside _stream_openai_response
    - But the final text response needs to be saved after all tools finish
    """
    await websocket.send_json({"type": "start"})
    
    # Get conversation: [system_prompt, user1, assistant1, user2, ...]
    messages = cm.get_messages()
    
    # Stream response from OpenAI (handles tools internally)
    assistant_response = await _stream_openai_response(messages, cm, websocket)
    
    # Save assistant's final response to conversation history
    if assistant_response:
        cm.add_message("assistant", assistant_response)
    
    await websocket.send_json({"type": "end"})


async def _stream_openai_response(messages, cm, websocket, depth=0):
    """
    Stream OpenAI response and handle tool calls recursively.
    
    CONVERSATION HISTORY TRACKING:
    ================================
    This function adds 3 types of messages to cm.messages:
    
    1. Tool Call (role="assistant", tool_calls=[...])
       - When LLM wants to run bash command
       - Added via cm.add_tool_call()
    
    2. Tool Result (role="tool", content="command output")
       - The bash command's output
       - Added via cm.add_tool_result()
    
    3. Final Text Response (role="assistant", content="text")
       - The LLM's final answer after tool execution
       - Returned to process_message() which saves it
    
    WHY RECURSIVE:
    ==============
    LLM may call bash_tool → we execute → LLM sees result → calls bash_tool again
    We recurse with updated messages each time, building history:
    
    [user: "list files"] 
      → [assistant: tool_call(ls)]
      → [tool: "file1.txt file2.txt"]
      → [assistant: tool_call(cat file1.txt)]
      → [tool: "contents..."]
      → [assistant: "Here are the files and contents..."]
    
    Args:
        messages: Full conversation history for OpenAI API
        cm: ConversationManager (where we save history)
        websocket: To stream tokens to client
        depth: Recursion depth (prevents infinite loops)
    
    Returns: 
        Final assistant text response (or error message)
    """
    # Prevent infinite loops
    if depth > 5:
        error_msg = "Error: Too many tool calls (max 5)"
        await websocket.send_json({"type": "error", "message": error_msg})
        return error_msg
    
    try:
        # Call OpenAI with full conversation + tool schema
        stream = await client.chat.completions.create(
            model="gpt-4o-mini",
            messages=messages,
            tools=[BASH_TOOL_SCHEMA],  # Tell LLM it can call bash_tool
            stream=True,
            temperature=0.7,
        )
        
        # Accumulate streamed response
        full_content = ""           # Text response
        tool_calls_buffer = {}      # Tool calls (streamed in chunks)
        
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
                    
                    # Accumulate tool call data (streamed piece by piece)
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
                    
                    # Execute in Docker container
                    output = cm.execute_bash_tool(command)
                    
                    # SAVE TO HISTORY: Tool call + result
                    cm.add_tool_call("bash_tool", args, tool_call["id"])
                    cm.add_tool_result(tool_call["id"], output)
                    
                    # Show result to client
                    await websocket.send_json({
                        "type": "tool_result",
                        "output": output
                    })
                    
                    # RECURSE: Send updated conversation back to LLM
                    # Now messages = [..., tool_call, tool_result]
                    updated_messages = cm.get_messages()
                    return await _stream_openai_response(
                        updated_messages, cm, websocket, depth + 1
                    )
        
        # No tool calls → return final text response
        return full_content
    
    except Exception as e:
        error_msg = f"OpenAI API Error: {str(e)}"
        await websocket.send_json({"type": "error", "message": error_msg})
        print(error_msg)
        return error_msg
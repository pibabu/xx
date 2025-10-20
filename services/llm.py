# services/llm.py
import asyncio
import os
import json
from dotenv import load_dotenv
from openai import AsyncOpenAI
from services.bash_tool import execute_bash_command
from services.conversation_manager import ConversationManager

load_dotenv()

api_key = "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"
#os.getenv("OPENAI_API_KEY")
print(f"DEBUG: Read API_KEY: '{api_key}'")
if not api_key or not api_key.startswith("sk-"):
    print("❌ FATAL: OPENAI_API_KEY is not set correctly.")
    raise ValueError("Invalid OpenAI API Key configuration.")

client = AsyncOpenAI(api_key=api_key)

# Configuration constants
MODEL = "gpt-4o-mini"

SYSTEM_MESSAGE = {
    "role": "system",
    "content": (
        "You can use the tool 'call_bash' to run shell commands, TELL THE USER! "
        "if user says:ls - you use ls -la ; you just run the command via tool call and name relevant content, no lists"
        "readme files are intsructions for you! inform user about readme"
        #viel mehr kontext!! du bist in workind dir: etc verhalten
    )
    
}

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "call_bash",
            "description": "Execute a bash command inside a container and return its output.",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {
                        "type": "string",
                        "description": "The bash command to execute."
                    }
                },
                "required": ["command"],
            },
        },
    }
]



def build_messages(user_message: str, assistant_message=None, tool_result=None, tool_call_id=None):
    """
    Build messages array for OpenAI API calls.
    
    Args:
        user_message: The user's input message
        assistant_message: Optional assistant message with tool calls
        tool_result: Optional tool execution result
        tool_call_id: Optional tool call ID for tool response
    """
    messages = [SYSTEM_MESSAGE, {"role": "user", "content": user_message}]
    
    if assistant_message:
        messages.append(assistant_message)
    
    if tool_result and tool_call_id:
        messages.append({
            "role": "tool",
            "tool_call_id": tool_call_id,
            "name": "call_bash",
            "content": tool_result,
        })
    
    return messages


conversation_manager = ConversationManager(max_messages=50)

async def process_message(user_message: str, websocket, session_id: str):
    """
    Main entry point - now takes session_id to track conversation.
    
    Args:
        user_message: What the user typed
        websocket: Connection to send responses
        session_id: Unique ID for this conversation (WebSocket connection)
    """
    # Add user message to history
    conversation_manager.add_user_message(session_id, user_message)
    
    await websocket.send_json({"type": "start"})
    await _handle_llm_interaction(session_id, websocket)
    await websocket.send_json({"type": "end"})
    

# Update _handle_llm_interaction to use session history and store responses -fehlt noch

async def _handle_llm_interaction(user_message: str, websocket):
    """
    Process message and handle both normal and tool call responses.
    """
    try:
        # Step 1: Ask model (with function/tool support)
        completion = await client.chat.completions.create(
            model=MODEL,
            messages=build_messages(user_message),
            tools=TOOLS,
        )

        message = completion.choices[0].message

        # Step 2: Check if LLM requested a tool call
        if message.tool_calls:
            for tool_call in message.tool_calls:
                if tool_call.function.name == "call_bash":
                    args = json.loads(tool_call.function.arguments)
                    bash_cmd = args.get("command", "")
                    await websocket.send_json(
                        {"type": "info", "content": f"Executing bash: {bash_cmd}"}
                    )

                    # Step 3: Execute inside container
                    result = await execute_bash_command(bash_cmd)

                    # Step 4: Send result back to LLM for reasoning
                    follow_up = await client.chat.completions.create(
                        model=MODEL,
                        messages=build_messages(
                            user_message,
                            assistant_message=message,
                            tool_result=result,
                            tool_call_id=tool_call.id
                        ),
                        stream=True,
                    )

                    # Step 5: Stream final answer
                    async for chunk in follow_up:
                        if chunk.choices[0].delta.content:
                            await websocket.send_json({
                                "type": "token",
                                "content": chunk.choices[0].delta.content,
                            })
        else:
            # Normal text-only response (streaming)
            stream = await client.chat.completions.create(
                model=MODEL,
                messages=build_messages(user_message),
                stream=True,
            )
            async for chunk in stream:
                if chunk.choices[0].delta.content:
                    await websocket.send_json({
                        "type": "token",
                        "content": chunk.choices[0].delta.content,
                    })

    except Exception as e:
        await websocket.send_json(
            {"type": "error", "message": f"AI service error: {str(e)}"}
        )
        print(f"OpenAI API Error: {e}")
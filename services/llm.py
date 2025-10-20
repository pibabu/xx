import asyncio
import os
import subprocess
from dotenv import load_dotenv
from llama_index.core.llms import ChatMessage, MessageRole
from llama_index.llms.openai import OpenAI
from llama_index.core.tools import FunctionTool

load_dotenv()

# Store conversation history per WebSocket connection
# Why dict: Maps each websocket ID to its own conversation history
conversation_histories = {}


def execute_bash_command(command: str) -> str:
    """
    Execute a bash command and return its output.
    
    Args:
        command: The bash command to execute
        
    Returns:
        Command output or error message
        
    Why this exists: Allows the AI to run system commands when needed
    """
    try:
        # Run command with timeout to prevent hanging
        # capture_output=True: Captures both stdout and stderr
        # text=True: Returns string instead of bytes
        # timeout=30: Kills command after 30 seconds
        result = subprocess.run(
            command,
            shell=True,
            capture_output=True,
            text=True,
            timeout=30
        )
        
        # Combine stdout and stderr for complete picture
        output = result.stdout
        if result.stderr:
            output += f"\nErrors: {result.stderr}"
            
        return output if output else "Command executed successfully (no output)"
        
    except subprocess.TimeoutExpired:
        return "Error: Command timed out after 30 seconds"
    except Exception as e:
        return f"Error executing command: {str(e)}"


# Create LlamaIndex tool from our function
# Why FunctionTool: Automatically generates JSON schema from function signature
bash_tool = FunctionTool.from_defaults(
    fn=execute_bash_command,
    name="call_bash",
    description="Execute a bash command inside a container and return its output. Use this when you need to run system commands, check files, or perform system operations."
)

# Initialize OpenAI LLM with tool support
# Why LlamaIndex's OpenAI wrapper: Handles tool calling automatically
llm = OpenAI(
    model="gpt-4o-mini",
    api_key=os.getenv("OPENAI_API_KEY"),
    temperature=0.7
)


async def process_message(user_message: str, websocket):
    """
    Process user message with conversation history and tool support
    
    Flow:
    1. Retrieve or create conversation history for this connection
    2. Add user's message to history
    3. Send to LLM with tools available
    4. If LLM wants to use tools, execute them and get final response
    5. Stream response back to user
    6. Update conversation history
    
    Args:
        user_message: The user's input text
        websocket: WebSocket connection for streaming
    """
    # Get unique ID for this websocket connection
    # Why: Each user needs their own conversation history
    ws_id = id(websocket)
    
    # Initialize history for new connections
    if ws_id not in conversation_histories:
        conversation_histories[ws_id] = [
            ChatMessage(
                role=MessageRole.SYSTEM,
                content="You are a helpful assistant with access to bash commands. Use the call_bash tool when you need to execute system commands."
            )
        ]
    
    # Get this connection's history
    history = conversation_histories[ws_id]
    
    # Add user message to history
    history.append(ChatMessage(role=MessageRole.USER, content=user_message))
    
    # Signal start of response
    await websocket.send_json({"type": "start"})
    
    try:
        # Get response from LLM with tool support
        # Why chat with tools: LLM can decide if it needs to use bash_tool
        response = await llm.achat_with_tools(
            tools=[bash_tool],
            chat_history=history,
            user_msg=None  # Already in history
        )
        
        # Stream the response
        # Why iterate by character: Creates smooth typing effect
        # Alternative: Could use LLM streaming for token-by-token
        for char in response.message.content:
            await websocket.send_json({"type": "token", "content": char})
            # Small delay for visual effect (optional)
            await asyncio.sleep(0.01)
        
        # Add assistant's response to history
        history.append(ChatMessage(
            role=MessageRole.ASSISTANT,
            content=response.message.content
        ))
        
        # Limit history size to prevent memory issues
        # Why 20: Keeps ~10 exchanges (user + assistant pairs)
        # Why slice [-20:]: Keeps most recent messages
        if len(history) > 20:
            # Keep system message + recent history
            conversation_histories[ws_id] = [history[0]] + history[-19:]
    
    except Exception as e:
        await websocket.send_json({
            "type": "error",
            "message": f"AI service error: {str(e)}"
        })
        print(f"LLM Error: {e}")
    
    # Signal end of response
    await websocket.send_json({"type": "end"})


def cleanup_conversation(websocket):
    """
    Remove conversation history when websocket disconnects
    
    Why: Prevents memory leaks from storing disconnected sessions
    Call this from your websocket disconnect handler
    """
    ws_id = id(websocket)
    if ws_id in conversation_histories:
        del conversation_histories[ws_id]
        print(f"🧹 Cleaned up history for connection {ws_id}")
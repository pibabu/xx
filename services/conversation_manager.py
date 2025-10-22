# conversation_manager.py
import subprocess
import json
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Optional


class ConversationManager:
    """
    Manages LLM conversation state with Docker container integration.
    
    Handles:
    - System prompt loading from container
    - Message history accumulation
    - Tool call execution and response handling
    - Conversation persistence
    """
    
    def __init__(self, user_id: str, stateful: bool = True):
        """
        Initialize conversation manager.
        
        Args:
            user_id: Unique identifier for user's container
            stateful: If True, keeps messages in memory. If False, reloads each time.
        """
        self.user_id = user_id
        self.container_name = f"user_{user_id}"
        self.stateful = stateful
        self.messages: List[Dict] = []
        self.system_prompt: Optional[str] = None
        self._tool_call_counter = 0  # For unique tool call IDs
        
    def _exec(self, command: str) -> str:
        """
        Execute bash command inside user's Docker container.
        
        Args:
            command: Shell command to execute
            
        Returns:
            Command output as string
            
        Why: Provides isolated execution environment per user.
        Docker ensures commands can't escape sandbox.
        """
        full_cmd = ["docker", "exec", self.container_name, "bash", "-c", command]
        result = subprocess.run(
            full_cmd, 
            capture_output=True,  # Capture both stdout and stderr
            text=True,           # Return strings, not bytes
            timeout=30           # Prevent hanging commands
        )
        
        # Return stdout if successful, stderr if failed
        if result.returncode != 0:
            return f"Error (exit {result.returncode}): {result.stderr.strip()}"
        return result.stdout.strip()
    
    def load_system_prompt(self) -> str:
        """
        Read system prompt from container filesystem.
        
        Returns:
            System prompt content
            
        Why: System prompt defines LLM behavior. Storing it in the
        container allows per-user customization and version control.
        """
        if self.system_prompt is None:  # Cache to avoid repeated reads
            self.system_prompt = self._exec("cat /data/system_prompt.txt")
        return self.system_prompt
    
    def add_user_message(self, content: str):
        """Add user message to conversation history."""
        self.messages.append({
            "role": "user",
            "content": content
        })
    
    def add_assistant_message(self, content: str):
        """Add assistant text response to conversation history."""
        self.messages.append({
            "role": "assistant",
            "content": content
        })
    
    def add_tool_call(self, tool_name: str, arguments: Dict, result: str):
        """
        Add tool call and its result to conversation.
        
        Args:
            tool_name: Name of the tool (e.g., "bash_tool")
            arguments: Tool arguments as dict
            result: Tool execution result
            
        Why: OpenAI requires tool calls in specific format with IDs.
        This maintains the conversation structure the API expects.
        """
        call_id = f"call_{self._tool_call_counter}"
        self._tool_call_counter += 1
        
        # First: Add the assistant's tool call message
        self.messages.append({
            "role": "assistant",
            "content": None,  # Tool calls have no text content
            "tool_calls": [{
                "id": call_id,
                "type": "function",
                "function": {
                    "name": tool_name,
                    "arguments": json.dumps(arguments)
                }
            }]
        })
        
        # Second: Add the tool's response message
        self.messages.append({
            "role": "tool",
            "tool_call_id": call_id,
            "content": result
        })
    
    def get_messages(self) -> List[Dict]:
        """
        Get complete message list for OpenAI API.
        
        Returns:
            List with system prompt + conversation history
            
        Why: OpenAI expects messages as list with system message first.
        This formats our internal state into API-compatible structure.
        """
        system_prompt = self.load_system_prompt()
        return [
            {"role": "system", "content": system_prompt}
        ] + self.messages
    
    def execute_bash_tool(self, command: str) -> str:
        """
        Execute bash command via tool interface.
        
        Args:
            command: Shell command to run
            
        Returns:
            Command output or error message
            
        Why: Wraps _exec with tool-specific logic. Can add
        command validation, logging, or sandboxing here.
        """
        # Optional: Add command filtering here
        # dangerous = ["rm -rf", ":(){ :|:& };:"]
        # if any(d in command for d in dangerous):
        #     return "Command rejected: potentially dangerous"
        
        return self._exec(command)
    
    def save(self, conversation_dir: str = "/data/conversations"):
        """
        Persist conversation to container filesystem.
        
        Args:
            conversation_dir: Directory path inside container
            
        Why: Conversations are valuable data. Saving them enables:
        - Debugging LLM behavior
        - Training data collection
        - User conversation history
        - Audit trails
        """
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"conv_{self.user_id}_{timestamp}.json"
        
        # Create temp file on host
        tmpfile = f"/tmp/{filename}"
        with open(tmpfile, "w") as f:
            json.dump({
                "user_id": self.user_id,
                "timestamp": timestamp,
                "messages": self.messages
            }, f, indent=2)
        
        # Copy to container
        self._exec(f"mkdir -p {conversation_dir}")
        copy_cmd = ["docker", "cp", tmpfile, 
                    f"{self.container_name}:{conversation_dir}/{filename}"]
        subprocess.run(copy_cmd)
        
        # Cleanup temp file
        Path(tmpfile).unlink()
        
    def reset(self):
        """
        Clear conversation and trigger container reset.
        
        Why: Users may want fresh context. This saves current
        conversation, clears memory, and runs container reset script.
        """
        self.save()
        self._exec("bash /data/scripts/start_new_conversation.sh")
        self.messages = []
        self.system_prompt = None  # Will reload on next get_messages()
        self._tool_call_counter = 0


# Tool schema for OpenAI API
BASH_TOOL_SCHEMA = {
    "type": "function",
    "function": {
        "name": "bash_tool",
        "description": "Execute bash commands inside the user's isolated Docker container. Use for file operations, system queries, or running scripts in /data.",
        "parameters": {
            "type": "object",
            "properties": {
                "command": {
                    "type": "string",
                    "description": "The bash command to execute (e.g., 'ls -la /data' or 'python /data/script.py')"
                }
            },
            "required": ["command"]
        }
    }
}
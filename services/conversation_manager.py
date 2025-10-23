import subprocess
import json
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Optional


class ConversationManager:
    
    def __init__(self, user_id: str, stateful: bool = True):
        """
            stateful: If True, keeps messages in memory. If False, reloads each time.
        """
        self.user_id = user_id
        self.container_name = "david"          #  f"user_{user_id}"
        self.stateful = stateful
        self.messages: List[Dict] = []
        self.system_prompt: Optional[str] = None
        
    def _exec(self, command: str) -> str:
        
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
   
        if self.system_prompt is None:  # Cache to avoid repeated reads
            self.system_prompt = self._exec("cat /data_private/.readme.md")
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
    
    def add_tool_call(self, tool_name: str, arguments: Dict, tool_call_id: str):
        
        # Add the assistant's tool call message
        self.messages.append({
            "role": "assistant",
            "content": None,
            "tool_calls": [{
                "id": tool_call_id,
                "type": "function",
                "function": {
                    "name": tool_name,
                    "arguments": json.dumps(arguments)
                }
            }]
        })

    def add_tool_result(self, tool_call_id: str, result: str):
        # Add the tool's response message
        self.messages.append({
            "role": "tool",
            "tool_call_id": tool_call_id,
            "content": result
        })
    
    def get_messages(self) -> List[Dict]:    #  ✗ Error: 'list' object has no attribute 'get_messages'

        system_prompt = self.load_system_prompt()
        return [
            {"role": "system", "content": system_prompt}
        ] + self.messages
    
    def execute_bash_tool(self, command: str) -> str:

        # Optional: Add command filtering here
        # dangerous = ["rm -rf", ":(){ :|:& };:"]
        # if any(d in command for d in dangerous):
        #     return "Command rejected: potentially dangerous"
        
        return self._exec(command)
    
    def save(self, conversation_dir: str = "/data/conversations"):

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

        self.save()
        self._exec("bash /data/scripts/start_new_conversation.sh") ##???
        self.messages = []
        self.system_prompt = None  # Will reload on next get_messages()


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
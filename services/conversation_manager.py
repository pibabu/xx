import json
import subprocess
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Optional
from services.bash_tool import BASH_TOOL_SCHEMA, execute_bash_command
from services.subagent_manager import SubAgentManager



class ConversationManager:
    """
    Manages conversation state and executes commands inside a Docker container.
    """

    def __init__(self, user_hash: str):
        self.user_hash = user_hash
        self.container_name = self._find_container_by_hash(user_hash)
        self.messages: List[Dict] = []
        self.system_prompt: Optional[str] = None

    # ----------------------------------------------------------------------
    # Docker container management
    # ----------------------------------------------------------------------
    def _find_container_by_hash(self, user_hash: str) -> str:
        """Find running container with matching user_hash label."""
        result = subprocess.run(
            ["docker", "ps", "--filter", f"label=user_hash={user_hash}", 
             "--format", "{{.Names}}"],
            capture_output=True, text=True, timeout=5
        )
        container = result.stdout.strip()
        if not container:
            raise ValueError(f"No container found for user_hash: {user_hash}")
        return container

    # ----------------------------------------------------------------------
    # Command execution
    # ----------------------------------------------------------------------
    async def execute_bash_tool(self, command: str) -> str:
        """Execute bash command inside container."""
        return await execute_bash_command(command, self.container_name)

    # ----------------------------------------------------------------------
    # System prompt
    # ----------------------------------------------------------------------
    async def load_system_prompt(self) -> str:
        """Load system prompt from container's /llm/private/readme.md"""
        if self.system_prompt is None:
            try:
                self.system_prompt = await execute_bash_command(
                    "cat /llm/private/readme.md", 
                    self.container_name
                )
            except Exception:
                self.system_prompt = "You are a helpful AI assistant."
        return self.system_prompt

    async def get_messages(self) -> List[Dict]:
        """Return full message list with system prompt."""
        system_prompt = await self.load_system_prompt()
        return [{"role": "system", "content": system_prompt}] + self.messages

    # ----------------------------------------------------------------------
    # Message history
    # ----------------------------------------------------------------------
    def add_user_message(self, content: str):
        self.messages.append({"role": "user", "content": content})

    def add_assistant_message(self, content: str):
        self.messages.append({"role": "assistant", "content": content})

    def add_tool_call(self, tool_name: str, arguments: Dict, tool_call_id: str):
        self.messages.append({
            "role": "assistant",
            "content": None,
            "tool_calls": [{
                "id": tool_call_id,
                "type": "function",
                "function": {"name": tool_name, "arguments": json.dumps(arguments)}
            }]
        })

    def add_tool_result(self, tool_call_id: str, result: str):
        self.messages.append({
            "role": "tool",
            "tool_call_id": tool_call_id,
            "content": result
        })

    # ----------------------------------------------------------------------
    # Export conversation state
    # ----------------------------------------------------------------------
    def get_conversation_data(self) -> Dict:
        """Return conversation data as dict (for external persistence)."""
        return {
            "user_hash": self.user_hash,
            "timestamp": datetime.now().isoformat(),
            "messages": self.messages
        }
        
        
        

        
        
# ----------------------------------------------------------------------
# Tool schema for OpenAI API
# ----------------------------------------------------------------------
BASH_TOOL_SCHEMA = {
    "type": "function",
    "function": {
        "name": "bash_tool",
        "description": (
            "Execute bash commands inside the user's Docker container. "
            "Use this to read/write files, run scripts, check system state, "
            "or interact with anything in /llm/private directories."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "command": {
                    "type": "string",
                    "description": "The bash command to execute (e.g., 'ls -la /llm/private' or 'cat file.txt')."
                }
            },
            "required": ["command"]
        }
    }
}

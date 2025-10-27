import json
import subprocess
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Optional

from services.bash_tool import execute_bash_command 


class ConversationManager:
    """
    Manages conversation state and executes commands inside a Docker container.
    
    Key responsibilities:
    1. Find and track user's Docker container by user_hash label
    2. Load system prompt from container's /data_private/readme.md
    3. Maintain conversation history (user/assistant/tool messages)
    4. Execute bash commands inside container via bash_tool
    5. Persist conversations to container storage
    """

    def __init__(self, user_hash: str, stateful: bool = True):
        self.user_hash = user_hash
        self.container_name = self._find_container_by_hash(user_hash)
        self.stateful = stateful
        self.messages: List[Dict] = []
        self.system_prompt: Optional[str] = None
        print(f"✓ ConversationManager initialized for container: {self.container_name}")

    # ----------------------------------------------------------------------
    # Docker container management
    # ----------------------------------------------------------------------
    def _find_container_by_hash(self, user_hash: str) -> str:
        """Find running container with matching user_hash label."""
        try:
            result = subprocess.run(
                [
                    "docker", "ps",
                    "--filter", f"label=user_hash={user_hash}",
                    "--format", "{{.Names}}"
                ],
                capture_output=True,
                text=True,
                timeout=5
            )
        except subprocess.TimeoutExpired:
            raise RuntimeError("Timeout: could not query Docker for container label")

        container = result.stdout.strip()
        if not container:
            raise ValueError(f"No active container found for user_hash: {user_hash}")
        return container

    def container_exists(self) -> bool:
        """Check if container is still running."""
        result = subprocess.run(
            [
                "docker", "ps",
                "--filter", f"label=user_hash={self.user_hash}",
                "--format", "{{.Names}}"
            ],
            capture_output=True,
            text=True
        )
        return bool(result.stdout.strip())

    # ----------------------------------------------------------------------
    # Command execution inside container
    # ----------------------------------------------------------------------
    async def _exec(self, command: str) -> str:
        """
        Run bash command inside user's container.
        Uses bash_tool.execute_bash_command() for async execution.
        """
        return await execute_bash_command(command, self.container_name)

    async def execute_bash_tool(self, command: str) -> str:
        """
        Execute user-supplied bash command inside container.
        This is called when LLM invokes the bash_tool.
        """
        print(f"🔧 Executing bash command: {command}")
        result = await self._exec(command)
        print(f"✓ Command output: {result[:200]}...")  # Log first 200 chars
        return result

    # ----------------------------------------------------------------------
    # System prompt handling
    # ----------------------------------------------------------------------
    async def load_system_prompt(self) -> str:
        """
        Load system prompt from /data_private/readme.md inside container.
        Caches result to avoid repeated file reads.#
        """
        if self.system_prompt is None:
            print("📄 Loading system prompt from container...")
            try:
                # Read the system prompt file
                self.system_prompt = await self._exec("cat /data_private/readme.md") ###change: its : llm/private  where does it execute from?since we have working dir set to llm??
                
                # Validate we got content
                if not self.system_prompt or self.system_prompt.strip() == "":
                    print("⚠️  WARNING: System prompt is empty!")
                    self.system_prompt = "You are a helpful AI assistant with access to bash commands."
                else:
                    print(f"✓ System prompt loaded ({len(self.system_prompt)} chars)")
                    
            except Exception as e:
                print(f"✗ ERROR loading system prompt: {e}")
                # Fallback prompt
                self.system_prompt = "You are a helpful AI assistant with access to bash commands."
        
        return self.system_prompt

    async def get_messages(self) -> List[Dict]:
        """
        Return complete message list for OpenAI API:
        [system_message, ...conversation_history]
        """
        system_prompt = await self.load_system_prompt()
        return [{"role": "system", "content": system_prompt}] + self.messages

    # ----------------------------------------------------------------------
    # Conversation history management
    # ----------------------------------------------------------------------
    def add_user_message(self, content: str):
        """Add user message to conversation history."""
        self.messages.append({"role": "user", "content": content})
        print(f"👤 User message added ({len(content)} chars)")

    def add_assistant_message(self, content: str):
        """Add assistant's text response to conversation history."""
        self.messages.append({"role": "assistant", "content": content})
        print(f"🤖 Assistant message added ({len(content)} chars)")

    def add_tool_call(self, tool_name: str, arguments: Dict, tool_call_id: str):
        """
        Record that assistant called a tool.
        This follows OpenAI's tool calling format.
        """
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
        print(f"🔧 Tool call recorded: {tool_name}({arguments})")

    def add_tool_result(self, tool_call_id: str, result: str):
        """
        Record the output from a tool execution.
        This allows LLM to see what the tool returned.
        """
        self.messages.append({
            "role": "tool",
            "tool_call_id": tool_call_id,
            "content": result
        })
        print(f"✓ Tool result recorded ({len(result)} chars)")

    # ----------------------------------------------------------------------
    # Persistence
    # ----------------------------------------------------------------------
    def save(self, conversation_dir: str = "/data_private//conversations"): 
        """
        Save conversation to JSON file inside container.
        File format: conv_{user_hash}_{timestamp}.json
        """
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"conv_{self.user_hash}_{timestamp}.json"
        tmpfile = f"/tmp/{filename}"

        print(f"💾 Saving conversation to {filename}...")

        # Create JSON file locally first
        with open(tmpfile, "w") as f:
            json.dump({
                "user_hash": self.user_hash,
                "timestamp": timestamp,
                "messages": self.messages
            }, f, indent=2)

        # Copy to container's /data_private/conversations directory  ---change as well
        result = subprocess.run(
            ["docker", "cp", tmpfile, f"{self.container_name}:{conversation_dir}/{filename}"],
            capture_output=True,
            text=True
        )
        
        if result.returncode != 0:
            print(f"⚠️  WARNING: Failed to copy conversation to container: {result.stderr}")
        else:
            print(f"✓ Conversation saved to container")

        # Clean up temp file
        Path(tmpfile).unlink(missing_ok=True)

    async def reset(self):
        """
        Save current conversation and start fresh session.
        Calls container's start_new_conversation.sh script.
        """
        print("🔄 Resetting conversation...")
        self.save()
        
        try:
            await self._exec("bash /data/scripts/start_new_conversation.sh")
            print("✓ Container session reset")
        except Exception as e:
            print(f"⚠️  WARNING: Reset script failed: {e}")
        
        # Clear in-memory state
        self.messages = []
        self.system_prompt = None  # Will reload on next get_messages()
        print("✓ Conversation state cleared")


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
            "or interact with anything in /data or /data_private directories."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "command": {
                    "type": "string",
                    "description": "The bash command to execute (e.g. 'ls -la /data' or 'cat file.txt')."
                }
            },
            "required": ["command"]
        }
    }
}

##where does all the debugging print go? explain
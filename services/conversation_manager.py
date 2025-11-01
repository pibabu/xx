import json
import subprocess
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Optional
from services.bash_tool import BASH_TOOL_SCHEMA, execute_bash_command


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
        """Load and compose system prompt from multiple sources."""
        if self.system_prompt is None:
            try:
                readme = await execute_bash_command(
                    "cat /llm/private/readme.md",
                    self.container_name
                )

                try:
                    req = await execute_bash_command(
                        "cat /llm/private/requirements.md",
                        self.container_name
                    )
                except Exception:
                    req = ""

                working_dir = ""
                try:
                    pwd = await execute_bash_command("pwd", self.container_name)
                    working_dir = pwd.strip()

                    if working_dir:
                        tree_output = await execute_bash_command(
                            f"tree -L 3 -I 'node_modules|__pycache__|.git|venv' {working_dir}",
                            self.container_name
                        )
                    else:
                        tree_output = "Project structure unavailable"
                except Exception:
                    tree_output = "Project structure unavailable"

                self.system_prompt = self._compose_system_prompt(
                    readme, req, tree_output, working_dir
                )

            except Exception:
                self.system_prompt = "You are a helpful AI assistant."

        return self.system_prompt

    def _compose_system_prompt(
        self, readme: str, req: str, tree: str, working_dir: str
    ) -> str:
        """Combine all context into a structured system prompt."""
        parts = [readme]

        if req.strip():
            parts.append("\n\n# Project Requirements\n" + req)

        if tree.strip() and tree != "Project structure unavailable":
            parts.append(
                f"\n\n# Current Project Structure\n"
                f"Working Directory: {working_dir}\n\n"
                f"```\n{tree}\n```"
            )

        return "\n".join(parts)

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

    def get_conversation_data(self) -> Dict:
        """Return conversation data as dict (for external persistence)."""
        return {
            "user_hash": self.user_hash,
            "timestamp": datetime.now().isoformat(),
            "messages": self.messages
        }

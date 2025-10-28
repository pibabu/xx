import asyncio
import subprocess

BASH_TOOL_SCHEMA = {
    "type": "function",
    "function": {
        "name": "bash_tool",
        "description": (
            "Execute bash commands inside the user's Docker container. "
            "Use for file operations, system queries, or running scripts in /data."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "command": {
                    "type": "string",
                    "description": "The bash command to execute (e.g. 'ls -la /data')."
                }
            },
            "required": ["command"]
        }
    }
}

async def execute_bash_command(command: str, container_name: str) -> str:
    """Execute bash command in container asynchronously."""
    proc = await asyncio.create_subprocess_exec(
        "docker", "exec", container_name, "bash", "-c", command,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE
    )
    
    stdout, stderr = await proc.communicate()
    
    if proc.returncode != 0:
        return f"Error (exit {proc.returncode}):\n{stderr.decode()}"
    return stdout.decode()
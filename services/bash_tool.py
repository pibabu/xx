# mehr error handling und regex für andere tool calls, doppelte commands wie ls und cat in einem!
import asyncio

CONTAINER_NAME = "my_tool_container" ####

async def execute_bash_command(command: str) -> str:
    """
    Execute a bash command inside a running Docker container.

    Args:
        command (str): Bash command to execute (e.g., 'ls /', 'cat /etc/hosts')

    Returns:
        str: Combined stdout + stderr from the container
    """
    try:
        proc = await asyncio.create_subprocess_shell(
            f"docker exec {CONTAINER_NAME} bash -c '{command}'",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await proc.communicate()
        output = (stdout + stderr).decode().strip()
        return output or "(no output)"
    except Exception as e:
        return f"Error executing command: {e}"

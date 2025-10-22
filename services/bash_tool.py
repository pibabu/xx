# mehr error handling und regex für andere tool calls, doppelte commands wie ls und cat in einem!
import asyncio

CONTAINER_NAME = "my_tool_container" #### set varalbe

async def execute_bash_command(command: str) -> str:
 
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




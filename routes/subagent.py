import asyncio
import os
import json
from fastapi import APIRouter, HTTPException
from typing import List, Optional, Literal, Dict
from dotenv import load_dotenv
from openai import AsyncOpenAI
from services.bash_tool import BASH_TOOL_SCHEMA, execute_bash_command


load_dotenv()

router = APIRouter(prefix="/api/llm", tags=["llm"]) ##


@router.post("/quick")
async def quick_llm_call(
    prompt: str,
    system_prompt: str = "Execute the task and save results to a file using the bash tool.",
    user_hash: Optional[str] = None
):
    """
    One-time LLM call with bash tool support (for cron jobs, scripts, etc).
    Completely separate from conversation history - creates isolated execution context.
    """
    try:
        # Get container name from user_hash if provided, otherwise use a default
        container_name = f"code_env_{user_hash}" if user_hash else "code_env_default"
        
        # Create isolated message context
        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": prompt}
        ]
        
        # Execute with tools
        result, tool_calls_log = await _execute_quick_llm(
            container_name, 
            messages
        )
        
        return {
            "result": result,
            "tool_calls": tool_calls_log,
            "container": container_name,
            "timestamp": asyncio.get_event_loop().time()
        }
        
    except Exception as e:
        raise HTTPException(500, f"Quick LLM execution failed: {str(e)}")


async def _execute_quick_llm(
    container_name: str, 
    messages: List[Dict],
    depth: int = 0
) -> tuple[str, List[Dict]]:
    """
    Execute LLM call with bash tool support (isolated, no conversation state).
    Returns: (final_response, tool_calls_log)
    """
    
    if depth > 5:
        return "Error: Too many tool calls (max 5)", []
    
    tool_calls_log = []
    client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))
    
    try:
        response = await client.chat.completions.create(
            model="gpt-4o-mini",
            messages=messages,
            tools=[BASH_TOOL_SCHEMA],
            temperature=0.7,
        )
        
        message = response.choices[0].message
        
        # CASE 1: Tool calls
        if message.tool_calls:
            for tool_call in message.tool_calls:
                if tool_call.function.name == "bash_tool":
                    args = json.loads(tool_call.function.arguments)
                    command = args["command"]
                    
                    # Execute bash command directly
                    output = await execute_bash_command(container_name, command)
                    
                    # Log tool call
                    tool_calls_log.append({
                        "command": command,
                        "output": output,
                        "timestamp": asyncio.get_event_loop().time()
                    })
                    
                    # Add tool call and result to messages
                    messages.append({
                        "role": "assistant",
                        "content": None,
                        "tool_calls": [{
                            "id": tool_call.id,
                            "type": "function",
                            "function": {
                                "name": "bash_tool",
                                "arguments": tool_call.function.arguments
                            }
                        }]
                    })
                    
                    messages.append({
                        "role": "tool",
                        "tool_call_id": tool_call.id,
                        "content": output
                    })
            
            # Recurse with updated messages
            result, more_calls = await _execute_quick_llm(
                container_name, 
                messages, 
                depth + 1
            )
            tool_calls_log.extend(more_calls)
            return result, tool_calls_log
        
        # CASE 2: Text response
        elif message.content:
            return message.content, tool_calls_log
        
        return "Error: No response from LLM", tool_calls_log
        
    except Exception as e:
        error_msg = f"OpenAI API Error: {str(e)}"
        print(error_msg)
        return error_msg, tool_calls_log
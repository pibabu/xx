####ehhhh

import json
from typing import List, Dict, Optional
from openai import AsyncOpenAI
import os

class SubAgentManager:
    """
    Isolated LLM agent that can use tools internally without 
    polluting the main conversation history.
    """
    
    def __init__(self, container_name: str, system_prompt: str):
        self.container_name = container_name
        self.messages: List[Dict] = [{"role": "system", "content": system_prompt}]
        self.client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))
    
    async def run(self, task: str, max_iterations: int = 5) -> str:
        """
        Run agent with task, allow it to use bash_tool internally.
        Returns final text response only.
        """
        from services.bash_tool import execute_bash_command, BASH_TOOL_SCHEMA
        
        # Add user task
        self.messages.append({"role": "user", "content": task})
        
        for i in range(max_iterations):
            response = await self.client.chat.completions.create(
                model="gpt-4o-mini",
                messages=self.messages,
                tools=[BASH_TOOL_SCHEMA],
                temperature=0.7,
            )
            
            message = response.choices[0].message
            
            # If no tool calls, we're done
            if not message.tool_calls:
                final_response = message.content or ""
                self.messages.append({"role": "assistant", "content": final_response})
                return final_response
            
            # Process tool calls
            self.messages.append({
                "role": "assistant",
                "content": message.content,
                "tool_calls": [
                    {
                        "id": tc.id,
                        "type": "function",
                        "function": {
                            "name": tc.function.name,
                            "arguments": tc.function.arguments
                        }
                    }
                    for tc in message.tool_calls
                ]
            })
            
            # Execute each tool call
            for tool_call in message.tool_calls:
                if tool_call.function.name == "bash_tool":
                    args = json.loads(tool_call.function.arguments)
                    output = await execute_bash_command(args["command"], self.container_name)
                    
                    self.messages.append({
                        "role": "tool",
                        "tool_call_id": tool_call.id,
                        "content": output
                    })
        
        # Max iterations reached
        return "Agent reached maximum iterations without completing task."
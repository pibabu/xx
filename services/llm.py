import asyncio
import os
from dotenv import load_dotenv
from openai import AsyncOpenAI


load_dotenv()

client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))


async def process_message(user_message: str, websocket):
  
    await websocket.send_json({"type": "start"})

    await _openai_streaming_response(user_message, websocket)

    # Signal end of response
    await websocket.send_json({"type": "end"})


async def _openai_streaming_response(user_message: str, websocket):
 
    try:
        # Create streaming chat completion
        stream = await client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "You are a helpful assistant."},
                {"role": "user", "content": user_message},
            ],
            stream=True,  # Critical: enables streaming
            temperature=0.7,
        )

        # Process each chunk as it arrives
        async for chunk in stream:
            # Extract content from chunk
            if chunk.choices[0].delta.content:
                content = chunk.choices[0].delta.content

                # Send to frontend immediately
                await websocket.send_json({"type": "token", "content": content})

    except Exception as e:
        # Handle API errors gracefully
        await websocket.send_json(
            {"type": "error", "message": f"AI service error: {str(e)}"}
        )
        print(f"OpenAI API Error: {e}")
        
        
        
        
async def _openai_streaming_response(messages, websocket):
    try:
        stream = await client.chat.completions.create(
            model="gpt-4o-mini",
            messages=messages,
            stream=True,
            temperature=0.7,
        )
        async for chunk in stream:
    choice = chunk.choices[0]
    delta = choice.delta

    if "tool_calls" in delta:
        tool_call = delta.tool_calls[0]
        name = tool_call.function.name
        args = json.loads(tool_call.function.arguments)
        print(f"Tool call detected: {name} with args {args}")

        if name == "bash_tool":
            output = run_bash_tool(args["command"], user_id)
            cm.add_tool_call(name, args, output)

            # Now call the LLM again with the tool output
            tool_response = {
                "role": "tool",
                "tool_call_id": tool_call.id,
                "content": output
            }

            followup_msgs = cm.get_messages() + [tool_response]
            await _openai_streaming_response(followup_msgs, websocket)
            break

    elif delta.content:
        await websocket.send_json({"type": "token", "content": delta.content})




   # except Exception as e:
    #    await websocket.send_json({"type": "error", "message": f"AI error: {e}"})
     #   print(f"OpenAI API Error: {e}")



###
import asyncio
import os
from dotenv import load_dotenv
from openai import AsyncOpenAI


load_dotenv()

client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))


async def process_message(user_message: str, websocket):
    """
    Process user message and stream AI response

    Args:
        user_message: The user's input text
        websocket: WebSocket connection to stream response to

    Why async: Allows other users to be handled while waiting for AI response
    Why streaming: Shows response as it's generated (better UX)
    """

    # Signal start of response
    await websocket.send_json({"type": "start"})

    await _openai_streaming_response(user_message, websocket)

    # Signal end of response
    await websocket.send_json({"type": "end"})


async def _openai_streaming_response(user_message: str, websocket):
    """
    Real OpenAI streaming response

    How it works:
    1. Send message to OpenAI with stream=True
    2. OpenAI returns chunks (deltas) as they're generated
    3. Forward each chunk to frontend via WebSocket
    4. Frontend appends chunks to create smooth typing effect
    """
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
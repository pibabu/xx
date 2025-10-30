from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from typing import List, Dict, Optional, Literal

router = APIRouter(prefix="/api/conversation", tags=["conversation"])

class MessageEdit(BaseModel):
    role: Literal["user", "assistant", "tool"]
    content: str

class ConversationEditRequest(BaseModel):
    user_hash: str
    action: Literal["clear", "replace_last", "inject", "remove_last"]
    count: Optional[int] = Field(1, ge=1, le=20, description="Number of turns/messages to affect")
    new_messages: Optional[List[MessageEdit]] = Field(None, description="New messages for replace/inject")

@app.post("/edit")
async def edit_conversation(request: ConversationEditRequest):
    """
    Modify conversation history.
    
    Actions:
    - clear: Wipe all messages, start fresh
    - replace_last: Replace last N conversation turns with new_messages
    - inject: Insert messages at the end (useful for adding context)
    - remove_last: Delete last N messages
    """
    try:
        cm = conversation_managers.get(request.user_hash)
        if not cm:
            raise HTTPException(404, "Conversation not found")
        
        if request.action == "clear":
            cm.messages.clear()
            return {
                "status": "success",
                "action": "cleared",
                "message_count": 0
            }
        
        elif request.action == "replace_last":
            if not request.new_messages:
                raise HTTPException(400, "new_messages required for replace_last")
            
            # Remove last N messages (count = number of messages, not turns)
            messages_to_remove = min(request.count, len(cm.messages))
            cm.messages = cm.messages[:-messages_to_remove] if messages_to_remove > 0 else cm.messages
            
            # Add new messages
            for msg in request.new_messages:
                cm.messages.append({"role": msg.role, "content": msg.content})
            
            return {
                "status": "success",
                "action": "replaced",
                "removed_count": messages_to_remove,
                "added_count": len(request.new_messages),
                "total_messages": len(cm.messages)
            }
        
        elif request.action == "inject":
            if not request.new_messages:
                raise HTTPException(400, "new_messages required for inject")
            
            # Add messages to the end
            for msg in request.new_messages:
                cm.messages.append({"role": msg.role, "content": msg.content})
            
            return {
                "status": "success",
                "action": "injected",
                "added_count": len(request.new_messages),
                "total_messages": len(cm.messages)
            }
        
        elif request.action == "remove_last":
            messages_to_remove = min(request.count, len(cm.messages))
            cm.messages = cm.messages[:-messages_to_remove] if messages_to_remove > 0 else cm.messages
            
            return {
                "status": "success",
                "action": "removed",
                "removed_count": messages_to_remove,
                "total_messages": len(cm.messages)
            }
        
        else:
            raise HTTPException(400, f"Unknown action: {request.action}")
            
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"Failed to edit conversation: {str(e)}")

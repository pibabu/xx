from typing import List, Dict, Optional
import json

class ConversationManager:
    """
    Manages conversation history for AI chat sessions.
    
    Each WebSocket connection gets its own conversation history.
    We store the complete message chain including tool calls/results
    so the LLM has full context for follow-up questions.
    """
    
    def __init__(self, max_messages: int = 50):
        """
        Initialize the conversation manager.
        
        Args:
            max_messages: Maximum number of messages to keep in history
                         (prevents memory bloat on long conversations)
        """
        self.sessions: Dict[str, List[Dict]] = {}
        self.max_messages = max_messages
    
    def get_or_create_session(self, session_id: str) -> List[Dict]:
        """
        Get existing session history or create new empty one.
        
        Args:
            session_id: Unique identifier (we'll use WebSocket connection ID)
        
        Returns:
            List of message dictionaries for this session
        """
        if session_id not in self.sessions:
            self.sessions[session_id] = []
        return self.sessions[session_id]
    
    def add_user_message(self, session_id: str, content: str):
        """
        Add a user message to the conversation.
        
        This is what the human typed into the chat input.
        
        Args:
            session_id: Session identifier
            content: The user's message text
        """
        history = self.get_or_create_session(session_id)
        history.append({
            "role": "user",
            "content": content
        })
        self._trim_history(session_id)
    
    def add_assistant_message(self, session_id: str, content: Optional[str] = None, 
                             tool_calls: Optional[List] = None):
        """
        Add an assistant (AI) message to the conversation.
        
        This can be either:
        - A text response: content="I found 2 files"
        - A tool call request: tool_calls=[{...}]
        
        The OpenAI API requires us to store assistant messages with tool_calls
        even if there's no text content yet.
        
        Args:
            session_id: Session identifier
            content: The AI's text response (optional if making tool call)
            tool_calls: List of tool call objects from OpenAI API
        """
        history = self.get_or_create_session(session_id)
        message = {"role": "assistant"}
        
        if content:
            message["content"] = content
        
        if tool_calls:
            # Store the raw tool_calls object from OpenAI
            # We need this exact format to send back in follow-up requests
            message["tool_calls"] = tool_calls
        
        history.append(message)
        self._trim_history(session_id)
    
    def add_tool_result(self, session_id: str, tool_call_id: str, 
                       tool_name: str, result: str):
        """
        Add a tool execution result to the conversation.
        
        After the LLM requests a tool call and we execute it,
        we store the result so the LLM can reason about it.
        
        Example flow:
        1. User: "list files"
        2. Assistant: [tool_call to bash with id="call_abc123"]
        3. Tool result: "file1.txt\nfile2.py" with tool_call_id="call_abc123"
        4. Assistant: "I found 2 files..."
        
        Args:
            session_id: Session identifier
            tool_call_id: The ID from the assistant's tool_call (must match!)
            tool_name: Name of the tool that was called (e.g., "call_bash")
            result: The output from the tool execution
        """
        history = self.get_or_create_session(session_id)
        history.append({
            "role": "tool",
            "tool_call_id": tool_call_id,
            "name": tool_name,
            "content": result
        })
        self._trim_history(session_id)
    
    def get_messages_for_api(self, session_id: str, system_message: Dict) -> List[Dict]:
        """
        Get formatted message history ready to send to OpenAI API.
        
        The API expects: [system_msg, user_msg, assistant_msg, tool_msg, ...]
        We always prepend the system message (it sets the AI's behavior).
        
        Args:
            session_id: Session identifier
            system_message: The system prompt (defines AI behavior/tools)
        
        Returns:
            Complete message array ready for OpenAI API
        """
        history = self.get_or_create_session(session_id)
        return [system_message] + history
    
    def clear_session(self, session_id: str):
        """
        Delete a session's history (cleanup when WebSocket disconnects).
        
        This prevents memory leaks from abandoned sessions.
        """
        if session_id in self.sessions:
            del self.sessions[session_id]
    
    def _trim_history(self, session_id: str):
        """
        Keep only the most recent messages to prevent memory bloat.
        
        IMPORTANT: We keep complete "chunks" - don't split up a
        user→assistant→tool→assistant sequence or the API will break.
        
        Simple strategy: Remove oldest messages when limit exceeded.
        Better strategy (TODO): Remove oldest complete exchanges.
        """
        history = self.get_or_create_session(session_id)
        if len(history) > self.max_messages:
            # Remove oldest messages, keeping the most recent ones
            # Note: This is naive - ideally we'd keep complete exchanges
            self.sessions[session_id] = history[-self.max_messages:]
    
    def get_session_count(self) -> int:
        """Get number of active sessions (for monitoring)."""
        return len(self.sessions)
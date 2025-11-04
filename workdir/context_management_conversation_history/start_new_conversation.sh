#!/bin/bash

# Clear all conversation history and start fresh

### add: start new conversation + DIR readme or + parameter input 
export API_BASE="http://host.docker.internal:8000"
# same as ??  NEIN!  -> API_HOST: export API_BASE="${API_BASE:-http://localhost:8000}"
export USER_HASH="${USER_HASH:-unknown}"

echo "🔄 Starting new conversation..."

response=$(curl -s -X POST "${API_BASE}/api/conversation/edit" \
    -H "Content-Type: application/json" \
    -d "{
        \"user_hash\": \"$USER_HASH\",
        \"action\": \"clear\"
    }")

echo "$response" | jq '.'

if echo "$response" | jq -e '.status == "success"' > /dev/null; then
    echo "✅ Conversation cleared successfully"
    echo "📝 Starting fresh - next message will be the first"
else
    echo "❌ Failed to clear conversation"
    exit 1
fi
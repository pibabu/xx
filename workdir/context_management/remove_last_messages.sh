#!/bin/bash
# /llm/bin/undo_last_messages.sh
# Remove last N messages from conversation
# Usage: undo_last_messages.sh <count>
export API_BASE="${API_BASE:-http://${API_HOST}:${API_PORT}}"
export USER_HASH="${USER_HASH}"


COUNT=${1:-1}

echo "🗑️  Removing last $COUNT message(s)..."

response=$(curl -s -X POST "${API_BASE}/api/conversation/edit" \
    -H "Content-Type: application/json" \
    -d "{
        \"user_hash\": \"$USER_HASH\",
        \"action\": \"remove_last\",
        \"count\": $COUNT
    }")

echo "$response" | jq '.'

if echo "$response" | jq -e '.status == "success"' > /dev/null; then
    removed=$(echo "$response" | jq -r '.removed_count')
    echo "✅ Removed $removed message(s)"
else
    echo "❌ Failed to remove messages"
    exit 1
fi
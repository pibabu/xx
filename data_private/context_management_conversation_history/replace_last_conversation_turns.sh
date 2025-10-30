# Replace the last conversation turn(s) with new content
# Usage: replace_last_turns.sh <count> <user_msg> <assistant_msg>

source /llm/bin/common.sh

COUNT=${1:-1}
USER_MSG=${2:-""}
ASSISTANT_MSG=${3:-""}

if [ -z "$USER_MSG" ] || [ -z "$ASSISTANT_MSG" ]; then
    echo "Usage: replace_last_turns.sh <count> <user_message> <assistant_message>"
    exit 1
fi

echo "🔄 Replacing last $COUNT message(s)..."

# For a single turn, we replace 2 messages (user + assistant)
MESSAGES_TO_REPLACE=$((COUNT * 2))

# Create new messages array
NEW_MESSAGES=$(jq -n \
    --arg user "$USER_MSG" \
    --arg assistant "$ASSISTANT_MSG" \
    '[
        {"role": "user", "content": $user},
        {"role": "assistant", "content": $assistant}
    ]')

response=$(curl -s -X POST "${API_BASE}/api/conversation/edit" \
    -H "Content-Type: application/json" \
    -d "{
        \"user_hash\": \"$USER_HASH\",
        \"action\": \"replace_last\",
        \"count\": $MESSAGES_TO_REPLACE,
        \"new_messages\": $NEW_MESSAGES
    }")

echo "$response" | jq '.'

if echo "$response" | jq -e '.status == "success"' > /dev/null; then
    echo "✅ Replaced last $COUNT turn(s)"
else
    echo "❌ Failed to replace messages"
    exit 1
fi
export API_BASE="${API_BASE:-http://localhost:8000}"
export USER_HASH="${USER_HASH:-unknown}"

# Validate they exist
if [ "$USER_HASH" = "unknown" ]; then
    echo "⚠️  WARNING: USER_HASH not set!"
fi


get_conversation_data() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local filename="/llm/conversations/conv_${timestamp}.json"
    
    # Call API to get conversation data
    curl -s -X POST "${API_BASE}/api/conversation/export" \
        -H "Content-Type: application/json" \
        -d "{\"user_hash\": \"$USER_HASH\"}" > "$filename"
    
    echo "💾 Saved to: $filename"
}
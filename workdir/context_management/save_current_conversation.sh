#!/bin/bash
# ------------------------------------------------------------
# Function: get_conversation_data
# Purpose : Fetches conversation data from the API and saves it
#           as a JSON file. Allows an optional filename parameter.
# Usage   :
#    get_conversation_data                # saves to conv_<timestamp>.json
#    get_conversation_data custom.json    # saves to custom.json
# Notes   
#    - Default save path: /llm/private/conversation_history/
# ------------------------------------------------------------
export API_BASE="${API_BASE:-http://${API_HOST}:${API_PORT}}"
export USER_HASH="${USER_HASH}"

# Validate that USER_HASH exists
if [ "$USER_HASH" = "unknown" ]; then
    echo "⚠️  WARNING: USER_HASH not set!"
fi

get_conversation_data() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local filename=${1:-"/llm/private/conversation_history/conv_${timestamp}.json"}
    
    # Call API to get conversation data
    curl -s -X POST "${API_BASE}/api/conversation/export" \
        -H "Content-Type: application/json" \
        -d "{\"user_hash\": \"$USER_HASH\"}" > "$filename"
    
    echo "Saved to: $filename"
}

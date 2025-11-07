#!/bin/bash
export API_BASE="${API_BASE:-http://${API_HOST}:${API_PORT}}"
export USER_HASH="${USER_HASH}"


runonetimellm() {
    local prompt="$1"
    local system_prompt="${2:-You are a helpful assistant.}"
    
    curl -s -X POST "${API_BASE}/api/llm/quick" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg prompt "$prompt" \
            --arg system "$system_prompt" \
            '{prompt: $prompt, system_prompt: $system}'
        )" | jq -r '.result'
}
###mit bash


###überhaupt nötig?? für cron
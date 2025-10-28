# little helper for subagent

run_agent_task() {
    local task="$1"
    local system_prompt="${2:-You are a helpful assistant with bash access.}"
    
    curl -s -X POST "${API_BASE}/api/agent/run" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg task "$task" \
            --arg system "$system_prompt" \
            --arg hash "$USER_HASH" \
            '{user_hash: $hash, task: $task, system_prompt: $system}'
        )" | jq -r '.result'
}


#!/bin/bash
export API_BASE="${API_BASE:-http://${API_HOST}:${API_PORT}}"
export USER_HASH="${USER_HASH}"
export LOG_DIR="${LOG_DIR:-/app/logs/cron}"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

runonetimellm() {
    local prompt="$1"
    local system_prompt="${2:-Execute the task and save results to a file using the bash tool.}"
    local log_file="${LOG_DIR}/cron_$(date +%Y%m%d_%H%M%S).log"
    
    echo "=== Cron LLM Execution ===" >> "$log_file"
    echo "Timestamp: $(date -Iseconds)" >> "$log_file"
    echo "Prompt: $prompt" >> "$log_file"
    echo "System: $system_prompt" >> "$log_file"
    echo "---" >> "$log_file"
    
    # Make API call and capture full response
    local response=$(curl -s -X POST "${API_BASE}/api/llm" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg prompt "$prompt" \
            --arg system "$system_prompt" \
            --arg hash "$USER_HASH" \
            '{prompt: $prompt, system_prompt: $system, user_hash: $hash}'
        )")
    
    # Log full response
    echo "$response" | jq '.' >> "$log_file"
    
    # Extract and return result
    echo "$response" | jq -r '.result'
    
    echo "=== End ===" >> "$log_file"
    echo "" >> "$log_file"
}

# Example usage in cron
runonetimellm "Check disk usage and create a report in /app/reports/disk_usage.txt"
runonetimellm "Backup all Python files to /app/backups/ with timestamp" "You are a backup assistant. Use bash commands to complete the task."

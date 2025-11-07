



create new file with script like this, think about your task:


## remember thats its not an hardcoded script and llms are highly adaptable. you can change script any time

# Run task 
result=$(run_agent_task "analyze /data/logs and create report")

echo "Result: $result"

# Maybe run another task
result2=$(run_agent_task "compress the report")

echo "Result: $result2"

# ✅ NOW SAVE EVERYTHING AT ONCE
use bash to save in current file




#!/bin/bash
source /usr/local/bin/llm-utils.sh

# Run multiple LLM tasks -> wget webpage + condense information
echo "wget webpage ..."
analysis=$(runonetimellm "Analyze /data/logs and create a summary report")

echo "Compressing report..."
compression=$(runonetimellm "Suggest best compression method for text reports")

echo "Generating filename..."
filename=$(runonetimellm "Generate a filename for a log analysis report (format: report_YYYY-MM-DD.txt)")

# Save everything at once
cat > "/data/reports/$filename" << EOF
=== Log Analysis Report ===
Generated: $(date)

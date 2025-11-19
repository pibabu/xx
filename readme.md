A chatbot system that executes commands in isolated Docker environments, with conversation context automatically built from your project directories and files

## Features

- **Isolated Environments**: Each user gets their own Docker container with own workspace 
- **Communication inside Network**: Container/User share network and can communicate via shared volume 
- **Context-Aware**: Automatically loads project README, requirements, and file structure into system prompt
- **Command Execution**: Run bash commands safely inside containers; use Cron Jobs to automate task execution
- **Conversation Management**: Run Scripts inside Container to manage conversation history or create and manage files
- **Subagents**: Run Subagents for tasks that would otherwise pollute token window

## Context Engineering is just filesystem navigation - "Everything is a file"
- cd topics/coding/, cat README for context, run the scripts with parameters
- use subagent to grep through logs, save condensed answer in file
- add dynamic context by changing requirement.md -> injected into system prompt


**It's just Bash**
- no need to overload token window with tools -> inject them dynamically into conversation
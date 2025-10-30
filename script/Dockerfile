FROM ubuntu:latest


RUN apt-get update && apt-get install -y \
    apt-utils \
    curl \
    git \
    jq \
    tree \
    nano \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /llm/private/conversation_history


WORKDIR /llm



# Keep container running
CMD ["sleep", "infinity"]


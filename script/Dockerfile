FROM python:3.12-slim

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


#RUN pip install --no-cache-dir Jinja2

CMD ["sleep", "infinity"]

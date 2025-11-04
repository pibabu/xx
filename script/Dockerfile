FROM python:3.12-slim

RUN apt-get update && apt-get install -y \
    apt-utils \
    curl \
    git \
    jq \
    tree \
    nano \
    && rm -rf /var/lib/apt/lists/*



WORKDIR /llm    
## checken: Workdir in dockerfile /llm ; in d-compose: llm/private 


#RUN pip install --no-cache-dir Jinja2

CMD ["sleep", "infinity"]

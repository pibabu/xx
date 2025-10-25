FROM ubuntu:latest

# Install basic tools
RUN apt-get update && apt-get install -y \
    curl \
    vim \
    git \
    jq \
    tree \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /llm

# Keep container running
CMD ["sleep", "infinity"]


sudo yum install tree   #since  its ec2 amazon lunx we cant use apt right?adapt
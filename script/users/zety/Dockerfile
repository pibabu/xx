FROM ubuntu:latest

# Avoid interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Install basic tools
RUN apt-get update && apt-get install -y \
    bash \
    coreutils \
    curl \
    vim \
    less \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Create application directory structure under /app
# This avoids conflicts with system directories in root
RUN mkdir -p /app/private /app/shared && \
    chown -R 1000:1000 /app

# Switch to non-root user
USER 1000:1000

# Set working directory
WORKDIR /app/private

# Keep container running 
CMD ["sleep", "infinity"]
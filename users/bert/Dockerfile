FROM ubuntu:latest

# Install basic tools
RUN apt-get update && apt-get install -y \
    bash \
    coreutils \
    && rm -rf /var/lib/apt/lists/*

# The ubuntu:latest image already has a user with UID 1000 (named 'ubuntu')
# So we just need to set up the directories with correct ownership

# Create volume mount points with correct ownership
RUN mkdir -p /data_shared /data_private && \
    chown -R 1000:1000 /data_shared /data_private

# Copy initialization script
#COPY init.sh /docker-entrypoint.sh
#RUN chmod +x /docker-entrypoint.sh && \
 #   chown 1000:1000 /docker-entrypoint.sh

# Switch to the existing user with UID 1000
USER 1000:1000
WORKDIR /data_private

CMD ["sleep", "infinity"]
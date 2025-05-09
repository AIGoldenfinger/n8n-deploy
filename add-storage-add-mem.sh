#!/bin/bash

# Create persistent data directory
sudo mkdir -p /home/n8n-data
sudo chmod 777 /home/n8n-data

# Stop current n8n container
sudo docker stop n8n
sudo docker rm n8n

# Update startup script with persistent volume
cat > /tmp/startup.sh << 'EOF'
#!/bin/bash

# Function to start n8n container with persistent storage
start_n8n() {
  if ! docker ps -q --filter "name=n8n" | grep -q .; then
    echo "Starting n8n container with persistent storage..."
    docker rm -f n8n 2>/dev/null || true
docker run -d \
  --restart always \
  --name n8n \
  -p 5678:5678 \
  -v /home/n8n-data:/home/node/.n8n \
  -m 900m \
  --memory-swap 2G \
  -e NODE_OPTIONS="--max_old_space_size=384" \
  -e N8N_DISABLE_PRODUCTION_MAIN_PROCESS="true" \
  -e N8N_DISABLE_WORKFLOW_STATS="true" \
  -e N8N_PROTOCOL="https" \
  -e GENERIC_TIMEZONE="UTC" \
  -e WEBHOOK_URL="https://auto8i.serveo.net/" \
  -e N8N_HOST="auto8i.serveo.net" \
  n8nio/n8n:1.91.2
      n8nio/n8n
    echo "n8n started at $(date) with persistent storage"
  else
    echo "n8n is already running"
  fi
}

# Function to start serveo tunnel
start_serveo() {
  if ! pgrep -f "ssh -R auto8i.serveo.net:80:localhost:5678" > /dev/null; then
    echo "Starting serveo tunnel..."
    autossh -M 0 -o "ServerAliveInterval 30" -o "ServerAliveCountMax 3" -o "StrictHostKeyChecking=no" -R "auto8i.serveo.net:80:localhost:5678" serveo.net &
    echo "Serveo tunnel started at $(date)"
  else
    echo "Serveo tunnel is already running"
  fi
}

# Install updated script
sudo mv /tmp/startup.sh /usr/local/bin/startup.sh
sudo chmod +x /usr/local/bin/startup.sh

# Restart services
sudo systemctl restart always-running.service
sudo systemctl restart monitor.service

# Run startup script to apply changes immediately
sudo /usr/local/bin/startup.sh

echo "n8n persistent storage has been set up at /home/n8n-data"
echo "Your workflows and data will now persist across restarts"
echo "To verify the volume mount:"
echo "  - Docker: sudo docker inspect n8n | grep -A 10 Mounts"

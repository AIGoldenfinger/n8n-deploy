#!/bin/bash

# Update system
sudo apt-get update
sudo apt-get install -y autossh docker.io curl

# Enable and start docker
sudo systemctl enable docker
sudo systemctl start docker

# Create SSH key if it doesn't exist
if [ ! -f ~/.ssh/id_rsa ]; then
  ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa
fi

# Pull n8n docker image
sudo docker pull n8nio/n8n

# Create startup script
cat > /tmp/startup.sh << 'EOF'
#!/bin/bash

# Function to start n8n container
start_n8n() {
  if ! docker ps -q --filter "name=n8n" | grep -q .; then
    echo "Starting n8n container..."
    docker rm -f n8n 2>/dev/null || true
    docker run -d --name n8n --restart always -p 5678:5678 n8nio/n8n
    echo "n8n started at $(date)"
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

# Main monitoring loop
while true; do
  start_n8n
  start_serveo
  sleep 60
done
EOF

chmod +x /tmp/startup.sh
sudo mv /tmp/startup.sh /usr/local/bin/startup.sh

# Create crontab entries for root
sudo bash -c '(crontab -l 2>/dev/null; echo "@reboot /usr/local/bin/startup.sh > /var/log/startup.log 2>&1") | crontab -'
sudo bash -c '(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/startup.sh > /var/log/startup.log 2>&1") | crontab -'

# Create systemd service (belt and suspenders approach)
cat > /tmp/always-running.service << EOF
[Unit]
Description=Always running n8n and serveo
After=network.target docker.service
Wants=docker.service

[Service]
ExecStart=/usr/local/bin/startup.sh
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/always-running.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable always-running.service
sudo systemctl start always-running.service

# Setup monitoring service
cat > /tmp/monitor.service << EOF
[Unit]
Description=Monitor n8n and serveo
After=network.target

[Service]
ExecStart=/bin/bash -c 'while true; do pgrep -f "autossh -M 0" || /usr/local/bin/startup.sh; docker ps | grep n8n || /usr/local/bin/startup.sh; sleep 300; done'
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/monitor.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable monitor.service
sudo systemctl start monitor.service

# Add script to /etc/rc.local for triple redundancy
if [ ! -f /etc/rc.local ]; then
  echo '#!/bin/bash' | sudo tee /etc/rc.local
  sudo chmod +x /etc/rc.local
fi

sudo bash -c 'cat >> /etc/rc.local << EOF
#!/bin/bash
/usr/local/bin/startup.sh &
exit 0
EOF'

# Start services immediately
sudo /usr/local/bin/startup.sh

echo "Setup complete. n8n and serveo tunnel are now running and will restart automatically."
echo "To check status:"
echo "  - Docker: sudo docker ps"
echo "  - Serveo tunnel: ps aux | grep autossh"
echo "  - Logs: cat /var/log/startup.log"

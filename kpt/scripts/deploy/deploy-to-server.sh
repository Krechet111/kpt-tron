#!/bin/bash
set -e

# Configuration
REMOTE_USER="bisq"
REMOTE_HOST="89.23.100.234"
REMOTE_DIR="/home/bisq/kpt/kpt-tron"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "=== Starting Deployment to $REMOTE_HOST ==="
echo "Project Root: $PROJECT_ROOT"

# Set Java 8 for build compatibility (‼️ change path for different OS)
export JAVA_HOME="/Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home"
echo "Using JAVA_HOME: $JAVA_HOME"

# 1. Build
echo ">>> Building FullNode.jar..."
cd "$PROJECT_ROOT"
./gradlew :framework:buildFullNodeJar -x test

# 2. Prepare Remote Directory + sync deploy artifacts (unit/swap/sudoers helpers)
echo ">>> Preparing remote environment..."
ssh "$REMOTE_USER@$REMOTE_HOST" "mkdir -p $REMOTE_DIR/logs $REMOTE_DIR/deploy"
rsync -avz \
    "$SCRIPT_DIR/kpt-tron.service" \
    "$SCRIPT_DIR/setup-swap.sh" \
    "$SCRIPT_DIR/sudoers-kpt-tron" \
    "$SCRIPT_DIR/install-root.sh" \
    "$SCRIPT_DIR/kpt-tron-watchdog.sh" \
    "$SCRIPT_DIR/kpt-tron-watchdog.service" \
    "$SCRIPT_DIR/kpt-tron-watchdog.timer" \
    "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/deploy/"

# 3. Stop Remote Service (graceful, systemd-aware)
echo ">>> Stopping remote service..."
ssh "$REMOTE_USER@$REMOTE_HOST" "bash -s" << 'EOF'
    if systemctl cat kpt-tron.service >/dev/null 2>&1; then
        # Unconditional idempotent stop whenever the unit exists — do NOT branch on
        # is-active. A transient 'activating (auto-restart)'/'deactivating' state would
        # otherwise fall through to the pkill path below, killing the node OUTSIDE
        # systemd, which then auto-restarts it — racing the jar overwrite.
        echo "Graceful systemd stop (idempotent; up to 300s for checkpoint flush)..."
        sudo systemctl stop kpt-tron
        echo "✅ Stopped (or was already inactive)."
    elif pgrep -f 'FullNode.jar' >/dev/null; then
        echo "Legacy process (no systemd unit) — SIGTERM (graceful)..."
        pkill -TERM -f 'FullNode.jar'
        for i in $(seq 1 60); do pgrep -f 'FullNode.jar' >/dev/null || break; sleep 2; done
        echo "✅ Stopped."
    else
        echo "ℹ️  Node was not running."
    fi
EOF

# 4. Transfer artifacts
echo ">>> Transferring FullNode.jar + config.conf..."
rsync -avz "$PROJECT_ROOT/framework/build/libs/FullNode.jar" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/"
rsync -avz "$PROJECT_ROOT/framework/src/main/resources/config.conf" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/"

# 5. Start Remote Service
echo ">>> Starting remote service..."
ssh "$REMOTE_USER@$REMOTE_HOST" "bash -s" << 'EOF'
    if ! systemctl cat kpt-tron.service >/dev/null 2>&1; then
        echo "❌ kpt-tron.service not installed. Run: sudo bash /home/bisq/kpt/kpt-tron/deploy/install-root.sh"
        echo "   (skipping start — install the unit once, then re-run deploy or start-on-server.sh)"
        exit 1
    fi
    sudo systemctl start kpt-tron
    sleep 5
EOF

# 6. Verify
echo "=== Verifying Deployment ==="
ssh "$REMOTE_USER@$REMOTE_HOST" "bash -s" << 'EOF'
    if systemctl is-active --quiet kpt-tron; then
        echo "✅ SUCCESS: kpt-tron is active."
        systemctl status kpt-tron --no-pager -l | head -n 10
    else
        echo "❌ ERROR: kpt-tron is not active."
        journalctl -u kpt-tron --no-pager -n 20
        exit 1
    fi
EOF

echo "=== Deployment Complete ==="

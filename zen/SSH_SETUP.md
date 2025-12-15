# SSH Setup Guide for Bootstrap Script

This guide will help you set up passwordless SSH to your homeserver (tower) so the bootstrap script can automatically configure Syncthing.

## Quick Setup (5 minutes)

### Step 1: Generate SSH Key (if you don't have one)

```bash
ssh-keygen -t ed25519 -C "syncthing-automation"
# Press Enter to accept default location (~/.ssh/id_ed25519)
# Press Enter twice for no passphrase (or set one if you prefer)
```

### Step 2: Copy SSH Key to Tower

```bash
ssh-copy-id root@10.0.0.24
# You'll be prompted for the root password (one time only)
```

**If `ssh-copy-id` is not available, use this instead:**

```bash
cat ~/.ssh/id_ed25519.pub | ssh root@10.0.0.24 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

### Step 3: Test Passwordless SSH

```bash
ssh root@10.0.0.24 "echo 'SSH connection successful!'"
# Should work without asking for a password
```

### Step 4: Run Bootstrap Script

Now you can run the bootstrap script with SSH method:

```bash
export HOMESERVER_SSH="root@10.0.0.24" && \
curl -fsSL -H "Cache-Control: no-cache" "https://raw.githubusercontent.com/j4ck3/dotfiles/refs/heads/master/zen/bootstrap.sh?t=$(date +%s)" | bash -s -- "your-tailscale-key"
```

## Troubleshooting

### "Permission denied (publickey)"

**Problem:** SSH key is not authorized on tower.

**Solution:**

1. Make sure you copied the key: `ssh-copy-id root@10.0.0.24`
2. Check permissions on tower:
   ```bash
   ssh root@10.0.0.24 "chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
   ```

### "Connection refused" or "Host key verification failed"

**Problem:** Can't connect to tower or SSH host key changed.

**Solution:**

1. Test basic SSH connection: `ssh root@10.0.0.24`
2. If host key changed, remove old key:
   ```bash
   ssh-keygen -R 10.0.0.24
   ```
3. Then try connecting again and accept the new key

### "ssh-copy-id: command not found"

**Problem:** `ssh-copy-id` is not installed.

**Solution:** Use manual method:

```bash
cat ~/.ssh/id_ed25519.pub | ssh root@10.0.0.24 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

## Alternative: Use API Method Instead

If SSH setup is too complicated, you can use the API method instead:

```bash
# Get API key from tower
ssh root@10.0.0.24 "docker exec syncthing cat /config/config.xml | grep -oP '(?<=<apikey>)[^<]+' | head -1"

# Then use it in bootstrap script
export HOMESERVER_SYNC_URL="http://10.0.0.24:8384" && \
export HOMESERVER_SYNC_APIKEY="paste-api-key-here" && \
curl -fsSL -H "Cache-Control: no-cache" "https://raw.githubusercontent.com/j4ck3/dotfiles/refs/heads/master/zen/bootstrap.sh?t=$(date +%s)" | bash -s -- "your-tailscale-key"
```

**Note:** The API method requires SSH access to get the API key, so you still need SSH set up. But once you have the API key, you can use it directly without SSH.

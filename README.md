## Local Development

### Setup
1. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```

2. Fill in your `.env` file:
   ```plaintext
   # Required
   DISCORD_OVERMORTAL_BOT_TOKEN=your_bot_token_here
   DISCORD_OVERMORTAL_CHANNEL_ID=your_channel_id_here
   LOCAL_DEV=true

   # Optional (only if testing AWS features)
   AWS_REGION=ap-southeast-1
   AWS_ACCESS_KEY_ID=your_access_key_here
   AWS_SECRET_ACCESS_KEY=your_secret_key_here
   ```

### Dependencies
Install required Python packages:

```bash
pip install -r requirements.txt
```

### Running the bot
```bash
python src/bot.py
```

### Getting Discord Credentials
1. Create a bot at [Discord Developer Portal](https://discord.com/developers/applications)
2. Copy the bot token
3. Enable the bot in your server
4. Right-click the channel and "Copy ID" to get the channel ID

### Troubleshooting
- Ensure all required environment variables are set
- Check the logs for any connection issues
- Verify the bot has proper permissions in your Discord server
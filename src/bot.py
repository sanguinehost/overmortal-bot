import discord
from discord.ext import commands, tasks
from datetime import datetime, time, timedelta
import pytz
import os
import logging
from dotenv import load_dotenv
import boto3
from json import loads
import argparse
import watchtower

# Configure logging
logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)

# Console handler
console_handler = logging.StreamHandler()
console_handler.setLevel(logging.DEBUG)
console_formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
console_handler.setFormatter(console_formatter)

# CloudWatch handler
if not os.getenv('LOCAL_DEV'):
    cloudwatch_handler = watchtower.CloudWatchLogHandler(
        log_group='/sanguine-overmortal/discord-bot',
        log_stream_name=f'bot-{datetime.now().strftime("%Y-%m-%d")}',
        use_queues=True,
        create_log_group=True
    )
    cloudwatch_handler.setLevel(logging.DEBUG)
    cloudwatch_formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    cloudwatch_handler.setFormatter(cloudwatch_formatter)
    logger.addHandler(cloudwatch_handler)

logger.addHandler(console_handler)

# Load environment variables
load_dotenv()

# Add after imports, before bot setup
parser = argparse.ArgumentParser(description='Sanguine Overmortal Discord Bot')
parser.add_argument('--quiet', '-q', action='store_true', 
                   help='Suppress welcome message on startup')
args = parser.parse_args()

# Bot setup with intents
intents = discord.Intents.default()
intents.message_content = True  # Enable message content intent
intents.members = True         # Enable members intent
bot = commands.Bot(command_prefix='!', intents=intents)

# Add near the top with other globals
NOTIFICATION_CACHE = {}

def get_secrets():
    # Check if we're running locally (using environment variables)
    if os.getenv('LOCAL_DEV'):
        logger.info("Running in local development mode")
        return {
            'DISCORD_OVERMORTAL_BOT_TOKEN': os.getenv('DISCORD_OVERMORTAL_BOT_TOKEN'),
            'DISCORD_OVERMORTAL_CHANNEL_ID': os.getenv('DISCORD_OVERMORTAL_CHANNEL_ID')
        }
    
    # Try AWS Secrets Manager
    try:
        session = boto3.session.Session()
        client = session.client(
            service_name='secretsmanager',
            region_name=os.getenv('AWS_REGION', 'ap-southeast-1')
        )
        
        secret_response = client.get_secret_value(
            SecretId='/prod/sanguine-overmortal/discord-bot-v2'
        )
        secrets = loads(secret_response['SecretString'])
        logger.info("Successfully loaded secrets from AWS")
        
        # Validate secrets
        if not secrets['DISCORD_OVERMORTAL_CHANNEL_ID']:
            logger.error("Missing DISCORD_OVERMORTAL_CHANNEL_ID")
        if not secrets['DISCORD_OVERMORTAL_BOT_TOKEN']:
            logger.error("Missing DISCORD_OVERMORTAL_BOT_TOKEN")
            
        return secrets
    except Exception as e:
        logger.error(f"Failed to fetch secrets from AWS: {e}")
        
        # Fallback to environment variables
        logger.info("Falling back to environment variables")
        return {
            'DISCORD_OVERMORTAL_BOT_TOKEN': os.getenv('DISCORD_OVERMORTAL_BOT_TOKEN'),
            'DISCORD_OVERMORTAL_CHANNEL_ID': os.getenv('DISCORD_OVERMORTAL_CHANNEL_ID')
        }

# Load environment variables first
load_dotenv()

# Get secrets (either from AWS or environment variables)
secrets = get_secrets()
CHANNEL_ID = secrets['DISCORD_OVERMORTAL_CHANNEL_ID']
BOT_TOKEN = secrets['DISCORD_OVERMORTAL_BOT_TOKEN']

if not all([CHANNEL_ID, BOT_TOKEN]):
    logger.error("Missing required environment variables!")
    raise ValueError("Missing required environment variables!")

# Error handling
@bot.event
async def on_error(event, *args, **kwargs):
    logger.error(f"Error in {event}", exc_info=True)

# Event times (UTC+7)
EVENTS = {
    'Beast Invasion': {
        'times': [time(12, 0), time(18, 0)],
        'duration': timedelta(minutes=15),
        'days': ['daily']
    },
    'Sect Clash': {
        'times': [time(21, 0)],
        'duration': timedelta(minutes=15),
        'days': ['saturday']
    },
    'Otherworld Invasion': {
        'times': [time(10, 0)],
        'duration': timedelta(hours=12),
        'days': ['saturday', 'sunday']
    },
    'Demonbend Abyss': {
        'times': [time(9, 0)],
        'duration': timedelta(hours=13),
        'days': ['monday', 'wednesday', 'friday']
    },
    'World Apex': {
        'times': [time(21, 0)],
        'duration': timedelta(minutes=15),
        'days': ['sunday']
    },
    'Sect Meditation': {
        'times': [time(9, 0)],
        'duration': timedelta(hours=13),
        'days': ['tuesday', 'thursday']
    }
}

TRANSLATIONS = {
    'Beast Invasion': {
        'vi': 'Xâm Lược Thú Hoang',
        'en': 'Beast Invasion'
    },
    'Sect Clash': {
        'vi': 'Đấu Trường Tông Môn',
        'en': 'Sect Clash'
    },
    'Otherworld Invasion': {
        'vi': 'Xâm Lược Dị Giới',
        'en': 'Otherworld Invasion'
    },
    'Demonbend Abyss': {
        'vi': 'Vực Ma Giới',
        'en': 'Demonbend Abyss'
    },
    'World Apex': {
        'vi': 'Đỉnh Cao Thế Giới',
        'en': 'World Apex'
    },
    'Sect Meditation': {
        'vi': 'Tông Môn Tĩnh Tu',
        'en': 'Sect Meditation'
    },
    'notifications': {
        'starting_30': {
            'en': '⏰ {event} Starting in 30 Minutes!',
            'vi': '⏰ {event} Sẽ Bắt Đầu Trong 30 Phút!'
        },
        'starting_30_desc': {
            'en': 'Prepare yourself! {event} will begin at {time}!',
            'vi': 'Chuẩn bị! {event} sẽ bắt đầu lúc {time}!'
        },
        'starting_5': {
            'en': '🔔 {event} Starting Soon!',
            'vi': '🔔 {event} Sắp Bắt Đầu!'
        },
        'starting_5_desc': {
            'en': 'Get ready! {event} begins in 5 minutes!',
            'vi': 'Sẵn sàng! {event} bắt đầu trong 5 phút!'
        },
        'ending_30': {
            'en': '⚠️ {event} Ending Soon!',
            'vi': '⚠️ {event} Sắp Kết Thúc!'
        },
        'ending_30_desc': {
            'en': 'Warning: {event} will end in 30 minutes!',
            'vi': 'Cảnh báo: {event} sẽ kết thúc trong 30 phút!'
        },
        'bot_online': {
            'en': '🟢 Sanguine Overmortal Bot Online',
            'vi': '🟢 Bot Sanguine Overmortal Đã Hoạt Động'
        },
        'monitoring_events': {
            'en': 'I am now monitoring events and will send notifications for:',
            'vi': 'Tôi đang theo dõi và sẽ gửi thông báo cho các sự kiện:'
        },
        'timezone': {
            'en': 'All times are in UTC+7 (Bangkok time)',
            'vi': 'Tất cả thời gian theo UTC+7 (Giờ Bangkok)'
        }
    }
}

TIMEZONE = pytz.timezone('Asia/Bangkok')  # UTC+7

def get_notification_times(event_time, duration):
    start_time = datetime.combine(datetime.today(), event_time)
    end_time = start_time + duration
    
    notifications = {
        'pre_30': (start_time - timedelta(minutes=30)).time(),
        'pre_5': (start_time - timedelta(minutes=5)).time(),
    }
    
    # Only add end notification for events longer than 1 hour
    if duration > timedelta(hours=1):
        notifications['end_30'] = (end_time - timedelta(minutes=30)).time()
    
    return notifications

def clear_old_cache_entries():
    current_time = datetime.now(TIMEZONE)
    expired_keys = [
        key for key, timestamp in NOTIFICATION_CACHE.items()
        if (current_time - timestamp).total_seconds() > 120  # 2 minutes expiry
    ]
    if expired_keys:
        logger.debug(f"[Cache] Clearing {len(expired_keys)} expired entries")
    for key in expired_keys:
        del NOTIFICATION_CACHE[key]

def should_send_notification(event_name, notification_type, scheduled_time):
    # Create cache key using the rounded time to the nearest minute
    rounded_time = scheduled_time.replace(second=0, microsecond=0)
    cache_key = f"{event_name}_{notification_type}_{rounded_time.strftime('%Y-%m-%d_%H:%M')}"
    current_time = datetime.now(TIMEZONE)
    
    if cache_key in NOTIFICATION_CACHE:
        logger.debug(f"[Cache] Found existing notification for {cache_key}")
        return False
    
    logger.debug(f"[Cache] Creating new notification entry for {cache_key}")
    NOTIFICATION_CACHE[cache_key] = current_time
    return True

@tasks.loop(seconds=30)  # Check every 30 seconds
async def check_events():
    clear_old_cache_entries()
    channel = bot.get_channel(int(CHANNEL_ID))
    current_time = datetime.now(TIMEZONE)
    current_day = current_time.strftime('%A').lower()
    
    # Round current time to nearest minute for more reliable comparisons
    current_time = current_time.replace(second=0, microsecond=0)
    
    logger.debug(f"[TimeCheck] Current time: {current_time.strftime('%Y-%m-%d %H:%M:%S')} ({current_day})")
    
    for event_name, event_data in EVENTS.items():
        if 'daily' in event_data['days'] or current_day in event_data['days']:
            for event_time in event_data['times']:
                notif_times = get_notification_times(event_time, event_data['duration'])
                time_str = event_time.strftime('%H:%M')
                
                # Log event check
                logger.debug(f"[EventCheck] Checking {event_name} scheduled for {time_str}")
                
                # Check each notification time with a 1-minute window
                for notif_type, notif_time in notif_times.items():
                    target_minutes = notif_time.hour * 60 + notif_time.minute
                    current_minutes = current_time.hour * 60 + current_time.minute
                    time_diff = abs(target_minutes - current_minutes)
                    
                    logger.debug(f"[TimeCompare] {event_name} {notif_type}: Target={notif_time.strftime('%H:%M')} Current={current_time.strftime('%H:%M')} Diff={time_diff}min")
                    
                    if time_diff <= 1:  # Within 1 minute window
                        if should_send_notification(event_name, notif_type, current_time):
                            logger.info(f"[Notification] Triggering {notif_type} notification for {event_name} (scheduled: {time_str})")
                            await send_notification(channel, event_name, notif_type, time_str)
                        else:
                            logger.debug(f"[Cache] Notification for {event_name} {notif_type} was already sent")

async def send_notification(channel, event_name, notif_type, time_str):
    event_vi = TRANSLATIONS[event_name]['vi']
    event_en = TRANSLATIONS[event_name]['en']
    
    notification_configs = {
        'pre_30': {
            'title': TRANSLATIONS['notifications']['starting_30'],
            'desc': TRANSLATIONS['notifications']['starting_30_desc'],
            'color': 0x3498db
        },
        'pre_5': {
            'title': TRANSLATIONS['notifications']['starting_5'],
            'desc': TRANSLATIONS['notifications']['starting_5_desc'],
            'color': 0xFF9900
        },
        'end_30': {
            'title': TRANSLATIONS['notifications']['ending_30'],
            'desc': TRANSLATIONS['notifications']['ending_30_desc'],
            'color': 0xFF0000
        }
    }
    
    config = notification_configs[notif_type]
    embed = discord.Embed(
        title=f"{config['title']['en'].format(event=event_en)}\n{config['title']['vi'].format(event=event_vi)}",
        description=f"{config['desc']['en'].format(event=event_en, time=time_str)}\n{config['desc']['vi'].format(event=event_vi, time=time_str)}",
        color=config['color']
    )
    
    logger.info(f"Sending {notif_type} notification for {event_name}")
    await channel.send(embed=embed)

@bot.event
async def on_ready():
    logger.info(f'Bot is ready! Logged in as {bot.user}')
    
    try:
        channel_id = int(CHANNEL_ID)
        channel = bot.get_channel(channel_id)
        
        if channel is None:
            logger.error(f"Could not find channel with ID: {channel_id}")
            return
        
        # Only send welcome message if not in quiet mode
        if not args.quiet:
            # Create a rich embed for the startup message
            embed = discord.Embed(
                title="🌟 Sanguine Overmortal Bot",
                description="Your cultivation companion for Immortal Taoists",
                color=0x9B59B6  # Royal purple color
            )
            
            # Add server time field
            current_time = datetime.now(TIMEZONE)
            embed.add_field(
                name="🕒 Server Time",
                value=f"{current_time.strftime('%H:%M')} (UTC+7)",
                inline=False
            )
            
            # Add events field in English
            events_list_en = "\n".join([f"• {TRANSLATIONS[event]['en']}" for event in EVENTS.keys()])
            embed.add_field(
                name="📅 Monitored Events",
                value=events_list_en,
                inline=True
            )
            
            # Add events field in Vietnamese
            events_list_vi = "\n".join([f"• {TRANSLATIONS[event]['vi']}" for event in EVENTS.keys()])
            embed.add_field(
                name="📅 Sự Kiện Theo Dõi",
                value=events_list_vi,
                inline=True
            )
            
            # Add notification types field
            notification_types = (
                "• 30 minutes before start ⏰\n"
                "• 5 minutes before start 🔔\n"
                "• 30 minutes before end ⚠️"
            )
            embed.add_field(
                name="🔄 Notification Schedule",
                value=notification_types,
                inline=False
            )
            
            # Send the startup message
            await channel.send(embed=embed)
        else:
            logger.info("Welcome message suppressed (quiet mode)")
        
        # Start the event checking loop
        check_events.start()
        logger.info("Event checking loop started")
        
    except ValueError as e:
        logger.error(f"Invalid channel ID format: {CHANNEL_ID}")
    except Exception as e:
        logger.error(f"Error in on_ready: {str(e)}", exc_info=True)

# Secure bot run
if __name__ == "__main__":
    if not all([CHANNEL_ID, BOT_TOKEN]):
        logger.error("Missing required environment variables")
        exit(1)
    
    try:
        bot.run(BOT_TOKEN)
    except Exception as e:
        logger.error(f"Failed to start bot: {e}")
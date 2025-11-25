import redis.asyncio as redis
from motor.motor_asyncio import AsyncIOMotorClient
from app.core.config import settings

redis_client: redis.Redis = None
mongo_client: AsyncIOMotorClient = None

async def setup_redis():
    global redis_client
    redis_client = redis.from_url(
        settings.REDIS_URL, 
        encoding="utf-8", 
        decode_responses=True
    )

async def setup_mongo():
    global mongo_client
    mongo_client = AsyncIOMotorClient(settings.MONGO_URL)

async def close_connections():
    if redis_client:
        await redis_client.close()
    if mongo_client:
        mongo_client.close()

async def get_redis() -> redis.Redis:
    return redis_client
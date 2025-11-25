import asyncio
import json
import os
from motor.motor_asyncio import AsyncIOMotorClient
import redis.asyncio as redis

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")
MONGO_URL = os.getenv("MONGO_URL", "mongodb://localhost:27017")

async def process_queue():
    r = redis.from_url(REDIS_URL, decode_responses=True)
    mongo = AsyncIOMotorClient(MONGO_URL)
    db = mongo["pyron_db"]
    collection = db["signals"]
    
    print("Worker started. Listening for signals...")

    while True:
        try:
            result = await r.blpop("trading_signals", timeout=0)
            
            if result:
                key, message = result
                data = json.loads(message)
                
                # Save to Mongo
                await collection.insert_one(data)
                print(f"Saved: {data}")
                
        except Exception as e:
            print(f"Error: {e}")
            await asyncio.sleep(1)
if __name__ == "__main__":
    asyncio.run(process_queue())
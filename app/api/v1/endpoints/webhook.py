from fastapi import APIRouter, status, Depends
from app.schemas.payload import WebhookPayload
from app.core.database import get_redis
import redis.asyncio as redis
import json

router = APIRouter()

@router.post("/webhook", status_code=status.HTTP_202_ACCEPTED)
async def ingest_data(
    data: WebhookPayload, 
    r: redis.Redis = Depends(get_redis) 
):
    payload_json = json.dumps(data.payload)
    
    if r:
        await r.rpush("trading_signals", payload_json)
    
    return {
        "status": "buffered", 
        "message": "Payload received and queued"
    }
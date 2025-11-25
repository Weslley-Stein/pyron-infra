from fastapi import APIRouter, status, HTTPException
from app.schemas.payload import WebhookPayload
import json

router = APIRouter()

@router.post("/webhook", status_code=status.HTTP_202_ACCEPTED)
async def ingest_data(data: WebhookPayload):
    
    return {
        "status": "buffered", 
        "message": "Payload received and queued"
    }
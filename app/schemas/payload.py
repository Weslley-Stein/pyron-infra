from pydantic import BaseModel
from typing import Dict, Any

class WebhookPayload(BaseModel):
    payload: Dict[str, Any]
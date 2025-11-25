from fastapi import FastAPI
from contextlib import asynccontextmanager
from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware
from app.api.v1.router import api_router
from app.core import database

@asynccontextmanager
async def lifespan(app: FastAPI):
    await database.setup_redis()
    yield
    await database.close_connections()
app = FastAPI(title="Pyron Infra", lifespan=lifespan)

app.add_middleware(ProxyHeadersMiddleware, trusted_hosts="*")

app.include_router(api_router, prefix="/api/v1")

@app.get("/health")
def health_check():
    return {"status": "We are good!!!"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True, proxy_headers=True)
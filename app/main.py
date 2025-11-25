from fastapi import FastAPI
from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware
from app.api.v1.router import api_router

app = FastAPI(title="Pyron Infra")
app.add_middleware(ProxyHeadersMiddleware, trusted_hosts="*")
app.include_router(api_router, prefix="/api/v1")

@app.get("/health")
def health_check():
    return {"status": "We are good!!!"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True, proxy_headers=True)
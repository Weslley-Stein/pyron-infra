from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    PROJECT_NAME: str = "PyRon Infra"
    VERSION: str = "1.0.0"
    API_V1_STR: str = "/api/v1"
    
    REDIS_URL: str = "redis://localhost:6379/0"
    MONGO_URL: str = "mongodb://localhost:27017"

    class Config:
        case_sensitive = True

settings = Settings()
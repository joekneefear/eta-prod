from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    LOT_FILES_DIR: str = "/apps/exensio_data/data/jnd_lot"
    PORT: int = 8000

    class Config:
        env_file = ".env"

settings = Settings()

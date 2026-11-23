from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict


# Backend root directory: peersync_backend/
BACKEND_ROOT = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    firebase_project_id: str
    firebase_credentials_path: str

    model_config = SettingsConfigDict(
        env_file=BACKEND_ROOT / ".env",
        env_file_encoding="utf-8",
        extra="ignore"
    )


settings = Settings()

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

# Backend root directory: peersync_backend/
BACKEND_ROOT = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    firebase_project_id: str
    firebase_credentials_path: str

    # Comma-separated list of allowed CORS origins. "*" keeps the previous
    # development default; set this to the real app origins in production.
    cors_allow_origins: str = "*"

    @property
    def cors_origin_list(self) -> list[str]:
        return [
            origin.strip()
            for origin in self.cors_allow_origins.split(",")
            if origin.strip()
        ]

    model_config = SettingsConfigDict(
        env_file=BACKEND_ROOT / ".env",
        env_file_encoding="utf-8",
        extra="ignore"
    )


settings = Settings()

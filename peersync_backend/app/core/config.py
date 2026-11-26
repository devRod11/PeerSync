from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_ROOT = Path(__file__).resolve().parents[2]

class Settings(BaseSettings):
    # Firebase configuration
    firebase_project_id: str
    firebase_credentials_path: str

    # CORS configuration
    cors_allow_origins: str = "*"

    # Google Drive OAuth 2.0 configuration
    google_drive_client_id: str | None = None
    google_drive_client_secret: str | None = None
    google_drive_redirect_uri: str | None = None
    google_drive_folder_id: str | None = None
    google_drive_token_encryption_key: str | None = None

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
"""应用配置。环境变量以 SYMBIONT_ 前缀覆盖（docker-compose 中注入）。"""
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="SYMBIONT_", extra="ignore")

    app_name: str = "Symbiont Server — 共生之缚 后端"
    api_prefix: str = "/api/v1"
    database_url: str = (
        "mysql+pymysql://symbiont:symbiont@127.0.0.1:3306/symbiont?charset=utf8mb4"
    )
    redis_url: str = ""          # 可选：排行榜缓存
    secret_key: str = "dev-secret-change-me"   # 生产环境必须通过环境变量覆盖


settings = Settings()

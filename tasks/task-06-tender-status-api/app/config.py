"""Конфигурация сервиса.

Все настройки читаются из окружения. Значения по умолчанию рассчитаны на
локальный запуск через docker-compose и не содержат ничего, что нельзя
было бы положить в git: боевые креденшелы приходят только из окружения.
"""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="APP_", env_file=".env", extra="ignore")

    # Схема marketplace создаётся заданием 4 — сервис работает поверх неё.
    database_url: str = "postgresql+asyncpg://tender:tender@localhost:5434/tender_platform"
    db_schema: str = "marketplace"

    db_pool_size: int = 5
    db_max_overflow: int = 5
    db_echo: bool = False

    # Максимальный размер страницы. Ограничение жёсткое: без него один
    # запрос с limit=1000000 выгружает таблицу в память процесса.
    max_page_size: int = 200


@lru_cache
def get_settings() -> Settings:
    """Настройки читаются один раз за процесс."""
    return Settings()

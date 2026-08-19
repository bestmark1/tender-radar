"""Подключение к БД и выдача сессий."""

from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker, create_async_engine

from app.config import get_settings

_engine: AsyncEngine | None = None
_session_factory: async_sessionmaker[AsyncSession] | None = None


def get_engine() -> AsyncEngine:
    global _engine
    if _engine is None:
        settings = get_settings()
        _engine = create_async_engine(
            settings.database_url,
            echo=settings.db_echo,
            pool_size=settings.db_pool_size,
            max_overflow=settings.db_max_overflow,
            pool_pre_ping=True,  # отсеивает соединения, разорванные пулером/файрволом
        )
    return _engine


def get_session_factory() -> async_sessionmaker[AsyncSession]:
    global _session_factory
    if _session_factory is None:
        _session_factory = async_sessionmaker(
            get_engine(),
            expire_on_commit=False,  # объекты остаются читаемыми после commit,
            autoflush=False,          # иначе сериализация ответа лезет в БД
        )
    return _session_factory


async def get_session() -> AsyncGenerator[AsyncSession, None]:
    """Зависимость FastAPI: одна сессия на запрос.

    Транзакцией управляет сервисный слой — это он знает, какие операции
    обязаны быть атомарными. Здесь только гарантия, что сессия закроется.
    """
    factory = get_session_factory()
    async with factory() as session:
        yield session


async def dispose_engine() -> None:
    global _engine, _session_factory
    if _engine is not None:
        await _engine.dispose()
    _engine = None
    _session_factory = None

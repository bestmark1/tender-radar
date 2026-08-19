"""Точка входа приложения."""

from __future__ import annotations

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from sqlalchemy import text

from app.db import dispose_engine, get_engine
from app.errors import DomainError
from app.routers import tenders

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    yield
    # Пул соединений закрывается явно: без этого при остановке контейнера
    # соединения висят на стороне Postgres до таймаута.
    await dispose_engine()


def create_app() -> FastAPI:
    app = FastAPI(
        title="Тендер-радар — трекинг статусов тендеров",
        description=(
            "Сервис создания тендеров, смены их статуса и аудита переходов. "
            "Работает поверх схемы marketplace из задания 4."
        ),
        version="1.0.0",
        lifespan=lifespan,
    )

    @app.exception_handler(DomainError)
    async def domain_error_handler(_: Request, exc: DomainError) -> JSONResponse:
        """Единое место, где доменные ошибки становятся HTTP-ответами.

        Формат тела ответа один для всех ошибок — клиенту не приходится
        разбирать несколько вариантов в зависимости от кода.
        """
        return JSONResponse(
            status_code=exc.http_status,
            content={
                "error": {
                    "code": exc.code,
                    "message": exc.message,
                    "details": exc.details,
                }
            },
        )

    @app.get("/health", tags=["service"], summary="Проверка живости")
    async def health() -> dict[str, str]:
        """Health-check с реальным обращением к БД.

        Проверка, которая отвечает 200 просто потому, что процесс запущен,
        бесполезна: контейнер жив, а сервис не работает, и оркестратор
        продолжает слать на него трафик.
        """
        async with get_engine().connect() as conn:
            await conn.execute(text("select 1"))
        return {"status": "ok"}

    app.include_router(tenders.router)
    return app


app = create_app()

"""Зависимости FastAPI."""

from typing import Annotated

from fastapi import Depends, Header
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.service import TenderService

SessionDep = Annotated[AsyncSession, Depends(get_session)]


async def get_actor(
    x_actor: Annotated[
        str,
        Header(
            min_length=1,
            max_length=200,
            description="Идентификатор действующего лица (логин или id пользователя)",
        ),
    ],
) -> str:
    """Кто выполняет операцию.

    Заголовок — намеренная заглушка на месте настоящей аутентификации:
    в бою это поле берётся из проверенного JWT или сессии, и снаружи его
    подменить нельзя. Здесь важно другое — что аудит физически не может
    записаться без указания субъекта: заголовок обязателен, и запрос без
    него не дойдёт до сервисного слоя. Заменить заглушку на разбор токена
    можно правкой одной этой функции.
    """
    return x_actor.strip()


ActorDep = Annotated[str, Depends(get_actor)]


async def get_tender_service(session: SessionDep) -> TenderService:
    return TenderService(session)


ServiceDep = Annotated[TenderService, Depends(get_tender_service)]

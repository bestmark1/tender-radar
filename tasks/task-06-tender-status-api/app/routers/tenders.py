"""HTTP-эндпоинты трекинга тендеров.

Обработчики намеренно тонкие: разобрать запрос, вызвать сервис, отдать
ответ. Никаких запросов к БД и никаких правил предметной области здесь нет.
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Path, Query, status as http_status

from app.config import get_settings
from app.dependencies import ActorDep, ServiceDep
from app.schemas import (
    ErrorResponse,
    Page,
    StatusChangeRequest,
    StatusHistoryRead,
    TenderCreate,
    TenderRead,
)
from app.status import TenderStatus

router = APIRouter(prefix="/api/v1/tenders", tags=["tenders"])

TenderId = Annotated[uuid.UUID, Path(description="Идентификатор тендера")]


@router.post(
    "",
    response_model=TenderRead,
    status_code=http_status.HTTP_201_CREATED,
    summary="Создать тендер",
    description="Тендер создаётся в статусе «Черновик»; в историю пишется запись о создании.",
    responses={
        409: {"model": ErrorResponse, "description": "Тендер с таким номером и версией уже есть"},
        422: {"model": ErrorResponse, "description": "Заказчик не найден или данные некорректны"},
    },
)
async def create_tender(payload: TenderCreate, service: ServiceDep, actor: ActorDep) -> TenderRead:
    tender = await service.create(payload, actor=actor)
    return TenderRead.model_validate(tender)


@router.get("", response_model=Page[TenderRead], summary="Список тендеров")
async def list_tenders(
    service: ServiceDep,
    limit: Annotated[int, Query(ge=1)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
    status: TenderStatus | None = None,
    region_code: Annotated[str | None, Query(pattern=r"^[0-9]{2,3}$")] = None,
    customer_id: uuid.UUID | None = None,
) -> Page[TenderRead]:
    limit = min(limit, get_settings().max_page_size)
    items, total = await service.list(
        limit=limit,
        offset=offset,
        status=status,
        region_code=region_code,
        customer_id=customer_id,
    )
    return Page[TenderRead](
        items=[TenderRead.model_validate(item) for item in items],
        total=total,
        limit=limit,
        offset=offset,
    )


@router.get(
    "/{tender_id}",
    response_model=TenderRead,
    summary="Получить тендер",
    responses={404: {"model": ErrorResponse, "description": "Тендер не найден"}},
)
async def get_tender(tender_id: TenderId, service: ServiceDep) -> TenderRead:
    return TenderRead.model_validate(await service.get(tender_id))


@router.patch(
    "/{tender_id}/status",
    response_model=TenderRead,
    summary="Изменить статус тендера",
    description=(
        "Переводит тендер в новый статус и записывает переход в историю "
        "(кто, когда, с какого на какой и почему). Допустимые переходы: "
        "Черновик → Активен → Выигран | Проигран."
    ),
    responses={
        404: {"model": ErrorResponse, "description": "Тендер не найден"},
        409: {"model": ErrorResponse, "description": "Недопустимый переход или нехватка данных"},
    },
)
async def change_status(
    tender_id: TenderId,
    payload: StatusChangeRequest,
    service: ServiceDep,
    actor: ActorDep,
) -> TenderRead:
    tender = await service.change_status(
        tender_id, target=payload.to_status, actor=actor, reason=payload.reason
    )
    return TenderRead.model_validate(tender)


@router.get(
    "/{tender_id}/history",
    response_model=Page[StatusHistoryRead],
    summary="История изменений статуса",
    responses={404: {"model": ErrorResponse, "description": "Тендер не найден"}},
)
async def get_history(
    tender_id: TenderId,
    service: ServiceDep,
    limit: Annotated[int, Query(ge=1)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> Page[StatusHistoryRead]:
    limit = min(limit, get_settings().max_page_size)
    items, total = await service.history(tender_id, limit=limit, offset=offset)
    return Page[StatusHistoryRead](
        items=[StatusHistoryRead.model_validate(item) for item in items],
        total=total,
        limit=limit,
        offset=offset,
    )

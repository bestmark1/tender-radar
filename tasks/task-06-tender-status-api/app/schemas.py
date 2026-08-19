"""Схемы запросов и ответов (Pydantic v2).

Отделены от ORM-моделей намеренно: контракт API не должен меняться каждый
раз, когда в таблицу добавили служебную колонку, и наоборот — внутреннее
поле не должно утекать наружу просто потому, что оно есть в модели.
"""

from __future__ import annotations

import datetime as dt
import uuid
from decimal import Decimal

from typing import Generic, TypeVar

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.status import TenderStatus


class TenderCreate(BaseModel):
    reg_number: str = Field(min_length=1, max_length=40)
    version: int = Field(default=1, ge=1)
    customer_id: uuid.UUID
    title: str = Field(min_length=1, max_length=1000)
    region_code: str = Field(pattern=r"^[0-9]{2,3}$")
    law: str = Field(default="44", pattern=r"^(44|223)$")
    procedure_type: str = Field(default="auction")
    nmck_total: Decimal | None = Field(default=None, gt=0)
    published_at: dt.datetime | None = None
    submission_deadline: dt.datetime | None = None
    eis_url: str | None = None

    @field_validator("procedure_type")
    @classmethod
    def _known_procedure(cls, value: str) -> str:
        allowed = {"auction", "contest", "quotation", "single_supplier"}
        if value not in allowed:
            raise ValueError(f"допустимые значения: {', '.join(sorted(allowed))}")
        return value

    @model_validator(mode="after")
    def _deadline_after_publication(self) -> TenderCreate:
        # Дублирует CHECK в БД. Дублирование здесь осознанное: база — последний
        # рубеж и вернёт ошибку целостности, а валидация на входе даёт
        # клиенту внятное сообщение с указанием поля вместо 500-й.
        if (
            self.published_at is not None
            and self.submission_deadline is not None
            and self.submission_deadline <= self.published_at
        ):
            raise ValueError("submission_deadline должен быть позже published_at")
        return self


class StatusChangeRequest(BaseModel):
    to_status: TenderStatus
    reason: str | None = Field(default=None, max_length=2000)


class TenderRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    reg_number: str
    version: int
    customer_id: uuid.UUID
    title: str
    law: str
    procedure_type: str
    region_code: str
    status: TenderStatus
    nmck_total: Decimal | None
    published_at: dt.datetime | None
    submission_deadline: dt.datetime | None
    eis_url: str | None
    created_at: dt.datetime
    updated_at: dt.datetime


class StatusHistoryRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tender_id: uuid.UUID
    from_status: TenderStatus | None
    to_status: TenderStatus
    changed_by: str
    reason: str | None
    changed_at: dt.datetime


ItemT = TypeVar("ItemT")


class Page(BaseModel, Generic[ItemT]):
    """Ответ со страницей результатов.

    total отдаётся отдельным запросом COUNT: без него клиент не может
    отрисовать пагинацию, а «а есть ли ещё» по длине страницы угадывается
    неверно ровно на последней странице.
    """

    items: list[ItemT]
    total: int
    limit: int
    offset: int


class ErrorBody(BaseModel):
    code: str
    message: str
    details: dict[str, object] = Field(default_factory=dict)


class ErrorResponse(BaseModel):
    error: ErrorBody

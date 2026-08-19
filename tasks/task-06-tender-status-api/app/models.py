"""ORM-модели поверх схемы marketplace из задания 4.

Модели описывают только те таблицы, с которыми работает сервис трекинга.
Схема — источник истины; SQLAlchemy её не создаёт и не изменяет, миграции
остаются обычными SQL-файлами (см. migrations/). Так схема одинаково
применима и для сервиса, и для аналитики из задания 4, и её не приходится
держать в двух описаниях сразу.
"""

from __future__ import annotations

import datetime as dt
import uuid

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    MetaData,
    Numeric,
    String,
    Text,
    func,
)
from sqlalchemy.dialects.postgresql import UUID as PgUUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship

SCHEMA = "marketplace"


class Base(DeclarativeBase):
    metadata = MetaData(schema=SCHEMA)


class Company(Base):
    __tablename__ = "companies"

    id: Mapped[uuid.UUID] = mapped_column(PgUUID(as_uuid=True), primary_key=True)
    inn: Mapped[str] = mapped_column(Text)
    short_name: Mapped[str] = mapped_column(Text)
    region_code: Mapped[str] = mapped_column(Text)
    is_customer: Mapped[bool] = mapped_column(Boolean)
    is_supplier: Mapped[bool] = mapped_column(Boolean)


class Tender(Base):
    __tablename__ = "tenders"

    id: Mapped[uuid.UUID] = mapped_column(
        PgUUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid()
    )
    reg_number: Mapped[str] = mapped_column(Text)
    version: Mapped[int] = mapped_column(Integer, default=1)
    customer_id: Mapped[uuid.UUID] = mapped_column(
        PgUUID(as_uuid=True), ForeignKey(f"{SCHEMA}.companies.id")
    )
    title: Mapped[str] = mapped_column(Text)
    law: Mapped[str] = mapped_column(Text, default="44")
    procedure_type: Mapped[str] = mapped_column(Text, default="auction")
    region_code: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(Text, default="draft")
    nmck_total: Mapped[float | None] = mapped_column(Numeric(15, 2), nullable=True)
    published_at: Mapped[dt.datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    submission_deadline: Mapped[dt.datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    eis_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    history: Mapped[list[TenderStatusHistory]] = relationship(
        back_populates="tender",
        order_by="TenderStatusHistory.changed_at.desc()",
        lazy="raise",  # ленивую загрузку в async-коде ловим на этапе разработки,
    )                  # а не как ошибку в рантайме под нагрузкой


class TenderStatusHistory(Base):
    __tablename__ = "tender_status_history"

    id: Mapped[uuid.UUID] = mapped_column(
        PgUUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid()
    )
    tender_id: Mapped[uuid.UUID] = mapped_column(
        PgUUID(as_uuid=True), ForeignKey(f"{SCHEMA}.tenders.id", ondelete="CASCADE")
    )
    from_status: Mapped[str | None] = mapped_column(Text, nullable=True)
    to_status: Mapped[str] = mapped_column(Text)
    changed_by: Mapped[str] = mapped_column(String)
    reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    changed_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    tender: Mapped[Tender] = relationship(back_populates="history", lazy="raise")

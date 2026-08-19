"""Общая обвязка тестов.

Тесты идут против настоящего PostgreSQL, а не мока или SQLite. Половина
проверяемой здесь логики живёт в самой схеме — CHECK-констрейнты,
уникальные индексы, SELECT ... FOR UPDATE — и на моке она просто не
исполняется. Тест, который зелёный на моке и падает на проде, хуже, чем
отсутствие теста.
"""

from __future__ import annotations

import os
import uuid
from collections.abc import AsyncIterator

import pytest

# Настройки читаются при импорте приложения, поэтому подменяются до него.
os.environ.setdefault(
    "APP_DATABASE_URL",
    "postgresql+asyncpg://tender:tender@127.0.0.1:5432/tender_platform_test",
)

from httpx import ASGITransport, AsyncClient  # noqa: E402
from sqlalchemy import text  # noqa: E402

from app.db import dispose_engine, get_session_factory  # noqa: E402
from app.main import create_app  # noqa: E402

CUSTOMER_ID = uuid.UUID("11111111-1111-1111-1111-111111111111")
SUPPLIER_ID = uuid.UUID("33333333-3333-3333-3333-333333333333")


@pytest.fixture(autouse=True)
async def clean_database() -> AsyncIterator[None]:
    """Чистая база перед каждым тестом.

    TRUNCATE ... CASCADE вместо пересоздания схемы: на порядок быстрее и
    сохраняет структуру, которую тесты как раз и проверяют.
    """
    factory = get_session_factory()
    async with factory() as session:
        await session.execute(
            text(
                "truncate marketplace.tender_status_history, marketplace.contractors, "
                "marketplace.bids, marketplace.lots, marketplace.tenders, "
                "marketplace.companies restart identity cascade"
            )
        )
        await session.execute(
            text(
                """
                insert into marketplace.companies
                    (id, inn, kpp, ogrn, short_name, region_code, is_customer, is_supplier)
                values
                    (:cust, '7700000001', '770001001', '1000000000001',
                     'ГБУ «Заказчик №1»', '77', true, false),
                    (:supp, '7700000003', '770001003', '1000000000003',
                     'ООО «Поставщик-А»', '77', false, true)
                """
            ),
            {"cust": CUSTOMER_ID, "supp": SUPPLIER_ID},
        )
        await session.commit()
    yield


@pytest.fixture
async def client() -> AsyncIterator[AsyncClient]:
    app = create_app()
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
        headers={"X-Actor": "test@example.com"},
    ) as ac:
        yield ac


@pytest.fixture(scope="session", autouse=True)
async def _dispose_engine_at_end() -> AsyncIterator[None]:
    yield
    await dispose_engine()


def tender_payload(**overrides: object) -> dict[str, object]:
    """Валидное тело запроса на создание тендера; поля переопределяются точечно."""
    payload: dict[str, object] = {
        "reg_number": "0173200001425000001",
        "version": 1,
        "customer_id": str(CUSTOMER_ID),
        "title": "Оказание услуг по комплексной уборке помещений",
        "region_code": "77",
        "law": "44",
        "procedure_type": "auction",
        "nmck_total": "1250000.00",
        "published_at": "2026-08-01T09:00:00+00:00",
        "submission_deadline": "2026-08-20T18:00:00+00:00",
    }
    payload.update(overrides)
    return payload

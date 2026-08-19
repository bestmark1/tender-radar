"""Эндпоинты создания, чтения и списка тендеров."""

from __future__ import annotations

import uuid

from httpx import AsyncClient

from tests.conftest import CUSTOMER_ID, SUPPLIER_ID, tender_payload


async def test_create_returns_draft(client: AsyncClient) -> None:
    response = await client.post("/api/v1/tenders", json=tender_payload())

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["status"] == "draft"          # создаётся всегда черновиком
    assert body["reg_number"] == "0173200001425000001"
    assert uuid.UUID(body["id"])


async def test_create_writes_creation_record_to_history(client: AsyncClient) -> None:
    created = (await client.post("/api/v1/tenders", json=tender_payload())).json()

    history = (await client.get(f"/api/v1/tenders/{created['id']}/history")).json()

    assert history["total"] == 1
    record = history["items"][0]
    assert record["from_status"] is None       # предыдущего статуса не было
    assert record["to_status"] == "draft"
    assert record["changed_by"] == "test@example.com"


async def test_create_rejects_duplicate_reg_number_and_version(client: AsyncClient) -> None:
    await client.post("/api/v1/tenders", json=tender_payload())

    response = await client.post("/api/v1/tenders", json=tender_payload())

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "duplicate_tender"


async def test_create_allows_new_version_of_same_notice(client: AsyncClient) -> None:
    """Новая редакция извещения — отдельная запись, а не дубликат."""
    await client.post("/api/v1/tenders", json=tender_payload())

    response = await client.post("/api/v1/tenders", json=tender_payload(version=2))

    assert response.status_code == 201


async def test_create_rejects_unknown_customer(client: AsyncClient) -> None:
    response = await client.post(
        "/api/v1/tenders", json=tender_payload(customer_id=str(uuid.uuid4()))
    )

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "company_not_found"


async def test_create_rejects_supplier_as_customer(client: AsyncClient) -> None:
    """Поставщик не может выступать заказчиком закупки."""
    response = await client.post(
        "/api/v1/tenders", json=tender_payload(customer_id=str(SUPPLIER_ID))
    )

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "company_not_found"


async def test_create_rejects_deadline_before_publication(client: AsyncClient) -> None:
    response = await client.post(
        "/api/v1/tenders",
        json=tender_payload(
            published_at="2026-08-20T09:00:00+00:00",
            submission_deadline="2026-08-01T09:00:00+00:00",
        ),
    )

    assert response.status_code == 422


async def test_create_requires_actor_header(client: AsyncClient) -> None:
    """Без указания субъекта запись в аудит невозможна — запрос не проходит."""
    response = await client.post(
        "/api/v1/tenders", json=tender_payload(), headers={"X-Actor": ""}
    )

    assert response.status_code == 422


async def test_get_unknown_tender_returns_404(client: AsyncClient) -> None:
    response = await client.get(f"/api/v1/tenders/{uuid.uuid4()}")

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "tender_not_found"


async def test_list_filters_by_status(client: AsyncClient) -> None:
    first = (await client.post("/api/v1/tenders", json=tender_payload())).json()
    await client.post("/api/v1/tenders", json=tender_payload(reg_number="0173200001425000002"))
    await client.patch(
        f"/api/v1/tenders/{first['id']}/status",
        json={"to_status": "active", "reason": "Заявка подана"},
    )

    active = (await client.get("/api/v1/tenders", params={"status": "active"})).json()
    drafts = (await client.get("/api/v1/tenders", params={"status": "draft"})).json()

    assert active["total"] == 1
    assert active["items"][0]["id"] == first["id"]
    assert drafts["total"] == 1


async def test_list_pagination_reports_total_beyond_page(client: AsyncClient) -> None:
    for i in range(5):
        await client.post(
            "/api/v1/tenders", json=tender_payload(reg_number=f"017320000142500{i:04d}")
        )

    page = (await client.get("/api/v1/tenders", params={"limit": 2, "offset": 0})).json()

    assert len(page["items"]) == 2
    assert page["total"] == 5      # total считается по всей выборке, не по странице
    assert page["limit"] == 2


async def test_list_limit_is_capped(client: AsyncClient) -> None:
    """Клиент не может запросить страницу произвольного размера."""
    page = (await client.get("/api/v1/tenders", params={"limit": 10_000})).json()

    assert page["limit"] == 200


async def test_list_filters_by_customer(client: AsyncClient) -> None:
    await client.post("/api/v1/tenders", json=tender_payload())

    page = (
        await client.get("/api/v1/tenders", params={"customer_id": str(CUSTOMER_ID)})
    ).json()

    assert page["total"] == 1

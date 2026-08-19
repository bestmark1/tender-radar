"""Смена статуса и аудит переходов — главное поведение сервиса."""

from __future__ import annotations

import uuid

from httpx import AsyncClient

from tests.conftest import tender_payload


async def _create(client: AsyncClient, **overrides: object) -> dict:
    return (await client.post("/api/v1/tenders", json=tender_payload(**overrides))).json()


async def test_full_lifecycle_draft_active_won(client: AsyncClient) -> None:
    tender = await _create(client)

    activated = await client.patch(
        f"/api/v1/tenders/{tender['id']}/status",
        json={"to_status": "active", "reason": "Заявка подана"},
    )
    won = await client.patch(
        f"/api/v1/tenders/{tender['id']}/status",
        json={"to_status": "won", "reason": "Признаны победителем"},
    )

    assert activated.status_code == 200
    assert activated.json()["status"] == "active"
    assert won.status_code == 200
    assert won.json()["status"] == "won"


async def test_history_records_who_when_and_why(client: AsyncClient) -> None:
    tender = await _create(client)
    await client.patch(
        f"/api/v1/tenders/{tender['id']}/status",
        json={"to_status": "active", "reason": "Заявка подана"},
        headers={"X-Actor": "manager@example.com"},
    )
    await client.patch(
        f"/api/v1/tenders/{tender['id']}/status",
        json={"to_status": "lost", "reason": "Проиграли по цене"},
        headers={"X-Actor": "director@example.com"},
    )

    history = (await client.get(f"/api/v1/tenders/{tender['id']}/history")).json()

    assert history["total"] == 3      # создание + два перехода
    # порядок обратный хронологическому: свежее изменение первым
    latest, middle, first = history["items"]

    assert (first["from_status"], first["to_status"]) == (None, "draft")
    assert (middle["from_status"], middle["to_status"]) == ("draft", "active")
    assert middle["changed_by"] == "manager@example.com"
    assert middle["reason"] == "Заявка подана"
    assert (latest["from_status"], latest["to_status"]) == ("active", "lost")
    assert latest["changed_by"] == "director@example.com"
    assert latest["reason"] == "Проиграли по цене"
    assert latest["changed_at"] >= middle["changed_at"]


async def test_skipping_active_is_rejected(client: AsyncClient) -> None:
    """Выиграть тендер, не переведя его в активные, нельзя."""
    tender = await _create(client)

    response = await client.patch(
        f"/api/v1/tenders/{tender['id']}/status", json={"to_status": "won"}
    )

    assert response.status_code == 409
    error = response.json()["error"]
    assert error["code"] == "invalid_status_transition"
    assert error["details"]["allowed"] == ["active"]   # клиенту сообщается, что можно


async def test_terminal_status_cannot_be_changed(client: AsyncClient) -> None:
    tender = await _create(client)
    await client.patch(f"/api/v1/tenders/{tender['id']}/status", json={"to_status": "active"})
    await client.patch(f"/api/v1/tenders/{tender['id']}/status", json={"to_status": "won"})

    response = await client.patch(
        f"/api/v1/tenders/{tender['id']}/status", json={"to_status": "lost"}
    )

    assert response.status_code == 409


async def test_transition_to_same_status_is_rejected(client: AsyncClient) -> None:
    tender = await _create(client)

    response = await client.patch(
        f"/api/v1/tenders/{tender['id']}/status", json={"to_status": "draft"}
    )

    assert response.status_code == 409
    assert "уже находится" in response.json()["error"]["message"]


async def test_activation_requires_publication_dates(client: AsyncClient) -> None:
    """Схема требует у неопубликованного тендера заполненных дат.

    Без проверки в сервисе клиент получил бы 500 с ошибкой целостности
    вместо указания, каких именно полей не хватает.
    """
    tender = await _create(client, published_at=None, submission_deadline=None)

    response = await client.patch(
        f"/api/v1/tenders/{tender['id']}/status", json={"to_status": "active"}
    )

    assert response.status_code == 409
    error = response.json()["error"]
    assert error["code"] == "tender_not_ready"
    assert set(error["details"]["missing_fields"]) == {"published_at", "submission_deadline"}


async def test_rejected_transition_leaves_no_trace(client: AsyncClient) -> None:
    """Отклонённый переход не должен ни менять статус, ни писать в историю."""
    tender = await _create(client)

    await client.patch(f"/api/v1/tenders/{tender['id']}/status", json={"to_status": "won"})

    current = (await client.get(f"/api/v1/tenders/{tender['id']}")).json()
    history = (await client.get(f"/api/v1/tenders/{tender['id']}/history")).json()
    assert current["status"] == "draft"
    assert history["total"] == 1      # только запись о создании


async def test_status_change_requires_actor(client: AsyncClient) -> None:
    tender = await _create(client)

    response = await client.patch(
        f"/api/v1/tenders/{tender['id']}/status",
        json={"to_status": "active"},
        headers={"X-Actor": ""},
    )

    assert response.status_code == 422


async def test_unknown_status_is_rejected(client: AsyncClient) -> None:
    tender = await _create(client)

    response = await client.patch(
        f"/api/v1/tenders/{tender['id']}/status", json={"to_status": "cancelled"}
    )

    assert response.status_code == 422


async def test_status_change_on_unknown_tender_returns_404(client: AsyncClient) -> None:
    response = await client.patch(
        f"/api/v1/tenders/{uuid.uuid4()}/status", json={"to_status": "active"}
    )

    assert response.status_code == 404


async def test_history_of_unknown_tender_returns_404(client: AsyncClient) -> None:
    """Пустая история и отсутствующий тендер — разные ответы."""
    response = await client.get(f"/api/v1/tenders/{uuid.uuid4()}/history")

    assert response.status_code == 404


async def test_concurrent_change_is_revalidated_after_lock(client: AsyncClient) -> None:
    """Переход перепроверяется по актуальному состоянию, а не по прочитанному до блокировки.

    Сценарий: тендер активен, конкурирующая транзакция переводит его в
    'won' и ещё не зафиксирована. В этот момент приходит запрос на переход
    в 'lost'.

    С SELECT ... FOR UPDATE запрос ждёт снятия блокировки, после чего в
    режиме READ COMMITTED перечитывает строку, видит уже 'won' и отвергает
    переход: выигранный тендер терминален.

    Без блокировки обычный SELECT вернул бы старое значение 'active',
    переход был бы признан допустимым, и UPDATE молча затёр бы 'won' на
    'lost' — тендер сменил бы исход, а в истории остался бы переход
    'active' → 'lost', которого не было.

    Именно этот тест отличает рабочую блокировку от её отсутствия: тест
    через asyncio.gather зелёный в обоих случаях, потому что запросы
    успевают разойтись во времени, а проверка одного лишь ожидания
    блокировки — потому что её берёт и сам UPDATE.
    """
    import asyncio

    from sqlalchemy import text

    from app.db import get_session_factory

    tender = await _create(client)
    await client.patch(f"/api/v1/tenders/{tender['id']}/status", json={"to_status": "active"})

    factory = get_session_factory()
    async with factory() as competitor:
        # Конкурент переводит тендер в 'won' и держит транзакцию открытой.
        await competitor.execute(
            text("update marketplace.tenders set status = 'won' where id = :id"),
            {"id": tender["id"]},
        )

        pending = asyncio.create_task(
            client.patch(
                f"/api/v1/tenders/{tender['id']}/status",
                json={"to_status": "lost", "reason": "Проиграли по цене"},
            )
        )
        done, _ = await asyncio.wait({pending}, timeout=1.0)
        assert not done, "запрос не дождался блокировки строки"

        await competitor.commit()

    response = await pending

    assert response.status_code == 409, (
        "переход применён по устаревшему статусу: строка не была перечитана под блокировкой"
    )
    assert response.json()["error"]["details"]["current_status"] == "won"

    final = (await client.get(f"/api/v1/tenders/{tender['id']}")).json()
    assert final["status"] == "won", "исход торгов затёрт конкурирующим переходом"

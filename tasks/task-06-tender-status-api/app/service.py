"""Бизнес-логика трекинга тендеров.

Слой ничего не знает про FastAPI: принимает данные, поднимает доменные
исключения, возвращает ORM-объекты. Это позволяет вызвать те же операции
из фонового воркера или CLI, не поднимая веб-приложение.
"""

from __future__ import annotations

import uuid

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app import errors
from app.models import Company, Tender, TenderStatusHistory
from app.schemas import TenderCreate
from app.status import INITIAL_STATUS, TenderStatus, allowed_from, can_transition


class TenderService:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    # ------------------------------------------------------------------
    # Создание
    # ------------------------------------------------------------------
    async def create(self, payload: TenderCreate, actor: str) -> Tender:
        """Создаёт тендер в статусе «Черновик» и пишет первую запись аудита.

        Тендер и запись истории создаются в одной транзакции: тендер без
        записи о создании — дыра в аудите, а запись без тендера нарушает FK.
        """
        customer = await self._session.get(Company, payload.customer_id)
        if customer is None:
            raise errors.CompanyNotFound(
                "заказчик не найден", customer_id=str(payload.customer_id)
            )
        if not customer.is_customer:
            raise errors.CompanyNotFound(
                "организация не является заказчиком", customer_id=str(payload.customer_id)
            )

        tender = Tender(
            **payload.model_dump(exclude_none=False),
            status=INITIAL_STATUS.value,
        )
        self._session.add(tender)

        try:
            # flush, а не commit: нужен сгенерированный id для записи истории,
            # но транзакция должна остаться открытой до конца операции.
            await self._session.flush()
        except IntegrityError as exc:
            await self._session.rollback()
            raise errors.DuplicateTender(
                "тендер с таким реестровым номером и версией уже существует",
                reg_number=payload.reg_number,
                version=payload.version,
            ) from exc

        self._session.add(
            TenderStatusHistory(
                tender_id=tender.id,
                from_status=None,          # создание: предыдущего статуса не было
                to_status=INITIAL_STATUS.value,
                changed_by=actor,
                reason="Создание тендера",
            )
        )
        await self._session.commit()
        await self._session.refresh(tender)
        return tender

    # ------------------------------------------------------------------
    # Смена статуса
    # ------------------------------------------------------------------
    async def change_status(
        self,
        tender_id: uuid.UUID,
        target: TenderStatus,
        actor: str,
        reason: str | None,
    ) -> Tender:
        """Переводит тендер в новый статус и логирует переход.

        Строка тендера блокируется через SELECT ... FOR UPDATE. Без блокировки
        два одновременных запроса прочитают один и тот же текущий статус,
        оба сочтут переход допустимым и запишут в историю два перехода из
        'active' — один в 'won', другой в 'lost'. Проверка допустимости и
        запись обязаны идти под одной блокировкой.
        """
        stmt = select(Tender).where(Tender.id == tender_id).with_for_update()
        tender = (await self._session.execute(stmt)).scalar_one_or_none()
        if tender is None:
            raise errors.TenderNotFound("тендер не найден", tender_id=str(tender_id))

        current = TenderStatus(tender.status)

        if current == target:
            # Не ошибка целостности, но и не изменение: писать в историю
            # переход в тот же статус нельзя (CHECK tsh_status_changed),
            # а молча возвращать 200 — вводить клиента в заблуждение.
            raise errors.InvalidStatusTransition(
                "тендер уже находится в этом статусе",
                current_status=current.value,
                target_status=target.value,
            )

        if not can_transition(current, target):
            allowed = sorted(s.value for s in allowed_from(current))
            raise errors.InvalidStatusTransition(
                "недопустимый переход статуса",
                current_status=current.value,
                target_status=target.value,
                allowed=allowed or ["— статус терминальный"],
            )

        self._ensure_ready_for(tender, target)

        tender.status = target.value
        self._session.add(
            TenderStatusHistory(
                tender_id=tender.id,
                from_status=current.value,
                to_status=target.value,
                changed_by=actor,
                reason=reason,
            )
        )
        # Смена статуса и запись аудита — одна транзакция. Если аудит
        # не записался, статус тоже не должен измениться: иначе в истории
        # появляются необъяснённые переходы.
        await self._session.commit()
        await self._session.refresh(tender)
        return tender

    @staticmethod
    def _ensure_ready_for(tender: Tender, target: TenderStatus) -> None:
        """Проверяет, что данных тендера хватает для целевого статуса.

        Схема (задание 4) требует у неопубликованного тендера пустых дат,
        а у любого другого — заполненных: CHECK tenders_published_fields.
        Без этой проверки попытка активировать черновик без дат вернула бы
        ошибку целостности и 500-ю вместо внятного объяснения.
        """
        if target is TenderStatus.DRAFT:
            return
        missing = [
            name
            for name in ("published_at", "submission_deadline")
            if getattr(tender, name) is None
        ]
        if missing:
            raise errors.TenderNotReadyForStatus(
                "для перевода из черновика нужны дата публикации и дедлайн подачи заявок",
                missing_fields=missing,
                target_status=target.value,
            )

    # ------------------------------------------------------------------
    # Чтение
    # ------------------------------------------------------------------
    async def get(self, tender_id: uuid.UUID) -> Tender:
        tender = await self._session.get(Tender, tender_id)
        if tender is None:
            raise errors.TenderNotFound("тендер не найден", tender_id=str(tender_id))
        return tender

    async def list(
        self,
        *,
        limit: int,
        offset: int,
        status: TenderStatus | None = None,
        region_code: str | None = None,
        customer_id: uuid.UUID | None = None,
    ) -> tuple[list[Tender], int]:
        conditions = []
        if status is not None:
            conditions.append(Tender.status == status.value)
        if region_code is not None:
            conditions.append(Tender.region_code == region_code)
        if customer_id is not None:
            conditions.append(Tender.customer_id == customer_id)

        # COUNT считается по тем же условиям, но без limit/offset —
        # иначе total совпадёт с размером страницы.
        total = await self._session.scalar(
            select(func.count()).select_from(Tender).where(*conditions)
        )
        stmt = (
            select(Tender)
            .where(*conditions)
            # Сортировка по created_at не строгая: у двух тендеров, созданных
            # в одну микросекунду, порядок между страницами мог бы «плавать»
            # и строка — потеряться. id как вторичный ключ делает порядок полным.
            .order_by(Tender.created_at.desc(), Tender.id.desc())
            .limit(limit)
            .offset(offset)
        )
        items = list((await self._session.execute(stmt)).scalars().all())
        return items, int(total or 0)

    async def history(
        self, tender_id: uuid.UUID, *, limit: int, offset: int
    ) -> tuple[list[TenderStatusHistory], int]:
        await self.get(tender_id)  # 404, если тендера нет: пустая история ≠ нет тендера

        total = await self._session.scalar(
            select(func.count())
            .select_from(TenderStatusHistory)
            .where(TenderStatusHistory.tender_id == tender_id)
        )
        stmt = (
            select(TenderStatusHistory)
            .where(TenderStatusHistory.tender_id == tender_id)
            .order_by(TenderStatusHistory.changed_at.desc(), TenderStatusHistory.id.desc())
            .limit(limit)
            .offset(offset)
        )
        items = list((await self._session.execute(stmt)).scalars().all())
        return items, int(total or 0)

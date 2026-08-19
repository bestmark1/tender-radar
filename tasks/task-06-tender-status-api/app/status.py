"""Машина состояний тендера.

Допустимые статусы и переходы вынесены из сервисного слоя в отдельный
модуль: это правило предметной области, оно тестируется отдельно от
работы с БД и от HTTP.
"""

from enum import StrEnum


class TenderStatus(StrEnum):
    DRAFT = "draft"      # Черновик
    ACTIVE = "active"    # Активен — заявка подана, идут торги
    WON = "won"          # Выигран
    LOST = "lost"        # Проигран


#: Куда можно перейти из каждого статуса.
#: Выигранный и проигранный тендер — терминальные состояния: исход торгов
#: свершился, и «передумать» задним числом нельзя. Если такая правка
#: понадобится (исправление ошибки оператора), это отдельная операция
#: со своими правами, а не рядовая смена статуса.
ALLOWED_TRANSITIONS: dict[TenderStatus, frozenset[TenderStatus]] = {
    TenderStatus.DRAFT: frozenset({TenderStatus.ACTIVE}),
    TenderStatus.ACTIVE: frozenset({TenderStatus.WON, TenderStatus.LOST}),
    TenderStatus.WON: frozenset(),
    TenderStatus.LOST: frozenset(),
}

#: Статус, с которого начинается жизнь тендера.
INITIAL_STATUS = TenderStatus.DRAFT


def allowed_from(status: TenderStatus) -> frozenset[TenderStatus]:
    return ALLOWED_TRANSITIONS[status]


def can_transition(current: TenderStatus, target: TenderStatus) -> bool:
    return target in ALLOWED_TRANSITIONS[current]


def is_terminal(status: TenderStatus) -> bool:
    return not ALLOWED_TRANSITIONS[status]

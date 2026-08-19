"""Машина состояний — проверяется без БД и без HTTP."""

import pytest

from app.status import ALLOWED_TRANSITIONS, TenderStatus, can_transition, is_terminal


def test_lifecycle_path_is_allowed() -> None:
    assert can_transition(TenderStatus.DRAFT, TenderStatus.ACTIVE)
    assert can_transition(TenderStatus.ACTIVE, TenderStatus.WON)
    assert can_transition(TenderStatus.ACTIVE, TenderStatus.LOST)


@pytest.mark.parametrize(
    ("current", "target"),
    [
        (TenderStatus.DRAFT, TenderStatus.WON),    # нельзя выиграть, не участвуя
        (TenderStatus.DRAFT, TenderStatus.LOST),
        (TenderStatus.WON, TenderStatus.ACTIVE),   # исход торгов не отыгрывается назад
        (TenderStatus.LOST, TenderStatus.ACTIVE),
        (TenderStatus.WON, TenderStatus.LOST),
        (TenderStatus.ACTIVE, TenderStatus.DRAFT),
    ],
)
def test_forbidden_transitions(current: TenderStatus, target: TenderStatus) -> None:
    assert not can_transition(current, target)


def test_terminal_statuses() -> None:
    assert is_terminal(TenderStatus.WON)
    assert is_terminal(TenderStatus.LOST)
    assert not is_terminal(TenderStatus.DRAFT)
    assert not is_terminal(TenderStatus.ACTIVE)


def test_every_status_is_declared() -> None:
    """Новый статус нельзя добавить, забыв описать для него переходы."""
    assert set(ALLOWED_TRANSITIONS) == set(TenderStatus)

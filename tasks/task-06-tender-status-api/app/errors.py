"""Доменные ошибки.

Сервисный слой не знает про HTTP: он поднимает доменные исключения, а их
отображение в коды ответов задаётся один раз в main.py. Иначе бизнес-логика
оказывается склеена с транспортом, и переиспользовать её, например, из
воркера очереди уже нельзя.
"""


class DomainError(Exception):
    """Базовая ошибка предметной области."""

    code = "domain_error"
    http_status = 400

    def __init__(self, message: str, **details: object) -> None:
        super().__init__(message)
        self.message = message
        self.details = details


class TenderNotFound(DomainError):
    code = "tender_not_found"
    http_status = 404


class CompanyNotFound(DomainError):
    code = "company_not_found"
    http_status = 422


class DuplicateTender(DomainError):
    code = "duplicate_tender"
    http_status = 409


class InvalidStatusTransition(DomainError):
    code = "invalid_status_transition"
    http_status = 409


class TenderNotReadyForStatus(DomainError):
    """Переход допустим машиной состояний, но данных тендера для него не хватает."""

    code = "tender_not_ready"
    http_status = 409

FROM python:3.12-slim

# PYTHONDONTWRITEBYTECODE — .pyc в слое образа только раздувают его.
# PYTHONUNBUFFERED — иначе логи приложения теряются при падении контейнера,
# оставаясь в буфере stdout.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /srv

# Зависимости отдельным слоем до копирования кода: правка исходников не
# должна инвалидировать кеш и заставлять переустанавливать пакеты.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

# Процесс не должен работать от root: при пробое приложения это разница
# между доступом к файлам сервиса и правами на всю файловую систему.
RUN useradd --system --uid 1001 appuser && chown -R appuser:appuser /srv
USER appuser

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]

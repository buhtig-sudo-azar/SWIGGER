# WCD Framework

Инструмент для моделирования и эксплуатации Web Cache Deception.

## Структура

- `wcd_framework.sh` — лаунчер (поднимает Flask + Nginx в RAM)
- `tools/wcd_gun.sh` — пулемёт (автоматизированная атака)
- `tools/magazines/` — обоймы (разделители, расширения, static dirs, эндпоинты)
- `app.py` — уязвимый бэкенд на Flask
- `nginx_vuln.conf` — уязвимый конфиг Nginx (кэширует 17 расширений)
- `nginx_secure.conf` — защищённый конфиг (фильтрация спецсимволов)

## Техники атак

1. **Delimiter Attack** — разделитель обманывает кэш (/profile;.css)
2. **Normalization Discrepancy** — расхождение декодирования %2f (требует unquote в middleware)
3. **Clean Extension** — catch-all маршрут + расширение, обходит secure-конфиг

## Статус

- vuln-конфиг: пробит (delimiter attack)
- secure-конфиг: пробит (clean extension через /profile/user.css)

## Журнал

| Дата | Что сделано | Сломано | Дальше |
|------|-------------|---------|--------|
| Апр 26 | raw команда, двойной Ctrl+C, версия 10.11 | raw режет ; без кавычек | Добавил пояснения |
| Апр 26 | Обнаружен обход secure-конфига через clean extension | — | Задокументирован |

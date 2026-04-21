# 🔫 Лысый Анатолий — WCD Gun v7.7

[![Bash](https://img.shields.io/badge/Bash-5.0%2B-121011?logo=gnu-bash&style=flat-square)](https://www.gnu.org/software/bash/)

[![Burp Suite](https://img.shields.io/badge/Burp%20Suite-Integration-orange?style=flat-square)](https://portswigger.net/burp)

> **Автоматизированный пулемёт для атак Web Cache Deception.**
> Превращает рутинный перебор разделителей в автоматический обстрел с логированием и интеграцией в Burp Suite.

<p align="center">
  <img src="https://raw.githubusercontent.com/buhtig-sudo-azar/SWIGGER/main/wcd_anatoly_scheme.svg" alt="WCD Attack Scheme" width="100%">
</p>

## 🎯 Проблема, которую мы решаем

Ты на пентесте. Перед тобой цель, потенциально уязвимая к Web Cache Deception. Чтобы проверить это вручную, нужно:
1. Подставить куки жертвы.
2. Сделать запрос с `;.css`.
3. Удалить куки.
4. Сделать повторный запрос и молиться на `X-Cache: HIT`.
5. Повторить для `?`, `#`, `%00`, `..` и 10 расширений.

Это **40+ ручных операций** в Repeater. Ты теряешь время и фокус.

## 💥 Решение: WCD Gun

`wcd_gun.sh` делает это сам. Тебе нужно только:
1. Указать цель.
2. Включить прокси Burp (опционально).
3. Скомандовать `fire`.

Пулемёт сам прогреет кэш, сам проверит все векторы, сам запишет результат в лог и подсветит успешные `HIT`'ы.

## ⚙️ Быстрый старт

```bash
# 1. Клонируй репозиторий
git clone https://github.com/ТВОЙ_НИК/ТВОЙ_РЕПО.git
cd ТВОЙ_РЕПО/tools

# 2. Дай права на исполнение
chmod +x wcd_gun.sh

# 3. Запуск с интеграцией Burp Suite (прокси 127.0.0.1:8082)
./wcd_gun.sh -P https://target-lab.com

# 4. В интерактивном режиме жми fire
wcd-gun > fire

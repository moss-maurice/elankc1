# Установка elankc1

Тач Elan для **PocketBook 740 Pro** (InkPad 3 Pro) с экраном **ED078KC1** (KC1).

Штатная книга понимает только родной тач Cypress. У KC1 контроллер Elan: без этого драйвера книга зависает на логотипе или загружается без тача.

Скрипты ищут `.ko` **рядом с собой**. В zip релиза и в `dist/` они уже лежат вместе. Ставить нужно с компьютера, не из SSH на книге.

Проверено на прошивке **U740-2.5.20.1154**. Прошивку обычного InkPad 3 (`U740`, `SWUPDATE.BIN`) на Pro **не ставить**.

## Перед установкой

1. Jailbreak **[pbjb](https://github.com/ezdiy/pbjb)** ([готовые файлы](https://github.com/ezdiy/pbjb/releases), v8). Два `.app` в `applications` → **`@Jailbreak`**, затем **`@Services`**.
2. USB на книге = **«Зарядка»**, не «Связь с ПК».
3. Книга должна отвечать по SSH: `root@169.254.0.1`.

Если книга уже зависла на логотипе с воткнутым KC1 — выньте шлейф тача, зажмите питание примерно на 30 секунд, дождитесь стола.

## Установка

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\install_elankc1.ps1
```

Linux:

```sh
./install_elankc1.sh
```

Пароль SSH спрашивается дважды. Дождитесь `[ok]  setup complete`. Книга сама **не** перезагрузится.

Дальше: **выключите книгу**, вставьте шлейф тача KC1, включите.

## Откат

Шлейф KC1 **вынуть**, иначе книга снова зависнет на логотипе.

Вернуть штатный тач Cypress:

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall_elankc1.ps1
```

```sh
./uninstall_elankc1.sh
```

Если раньше стояла старая версия с другими именами файлов:

```powershell
powershell -ExecutionPolicy Bypass -File .\restore_factory.ps1
```

```sh
./restore_factory.sh
```

Перед официальным обновлением ПО (только линейка **U740-2**) jailbreak снимите заранее: `@Jailbreak` / `@Services`.

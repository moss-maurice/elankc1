# Установка elankc1

Тач Elan для **PocketBook 740** (InkPad 3) и **740 Pro** (InkPad 3 Pro) с экраном **ED078KC1** (KC1).

Скрипты ищут `.ko` **рядом с собой**. Ставить с компьютера, не из SSH на книге. Готовый zip — в [Releases](https://github.com/moss-maurice/elankc1/releases).

> [!CAUTION]
>
> ### ОТКАЗ ОТ ОТВЕТСТВЕННОСТИ
>
> ВСЕ МОДИФИКАЦИИ ПРОГРАММНОЙ ЧАСТИ И МАТЕРИНСКОЙ ПЛАТЫ ПРОИЗВОДЯТСЯ НА СВОЙ СТРАХ И РИСК, ЭТО НЕМИНУЕМО ПРИВЕДЕТ К СЛЕТАНИЮ ГАРАНТИИ, УНИЧТОЖЕНИЮ УСТРОЙСТВА, ЗАХВАТУ ПЛАНЕТЫ ИНОПЛАНЕТНЫМИ ЦИВИЛИЗАЦИЯМИ И ЛУЧШЕ 100 РАЗ ПОДУМАТЬ ПЕРЕД ТЕМ, КАК ЧТО-ТО ДЕЛАТЬ. АВТОР СНИМАЕТ С СЕБЯ ЛЮБУЮ ОТВЕТСТВЕННОСТЬ, А ЛЮБЫЕ МОДИФИКАЦИИ ВЫ ПРОВОДИТЕ НА СВОЙ СТРАХ И РИСК.

> [!WARNING]
>
> ### ДОРАБОТКА ПЛАТЫ ОБЯЗАТЕЛЬНА
>
> Без выпила в материнской плате экран KC1 **не запустить**. Шлейф тача физически не садится в разъём — драйвер и jailbreak тут ни при чём.
>
> Пилить плату — на свой страх и риск. Автор ответственности не несёт: ни за сорванные дорожки, ни за короткое замыкание, ни за «кирпич».
>
> Как пилить и фото: [README репозитория](https://github.com/moss-maurice/elankc1#%D0%B4%D0%BE%D1%80%D0%B0%D0%B1%D0%BE%D1%82%D0%BA%D0%B0-%D0%BF%D0%BB%D0%B0%D1%82%D1%8B) и [сообщение на 4PDA](https://4pda.to/forum/index.php?showtopic=886480&view=findpost&p=144920298).

> [!IMPORTANT]
>
> После обновления прошивки патч **слетает**. Тач KC1 снова не работает, а накатить драйвер без живого тача почти нельзя: снова нужен jailbreak, а в меню без тача не попасть.
>
> Сохраните родную панель, если тач на ней ещё живой, либо **не обновляйте прошивку**.
>
> Проверено на 740 Pro, **U740-2.5.20.1154**. На обычном 740 шаги те же. Прошивки не мешать: на 740 только `U740`, на Pro только `U740-2`. Чужой `SWUPDATE.BIN` ставить нельзя.

## ⚙️ Установка

Одинаково для 740 и 740 Pro. Без jailbreak нет SSH и нельзя подменить модули тача.

1. Скачайте **[pbjb](https://github.com/ezdiy/pbjb)** v8: [готовые файлы](https://github.com/ezdiy/pbjb/releases). USB = **«Связь с ПК»**, два `.app` в папку `applications`. Запустите **`@Jailbreak`**, дождитесь успеха, затем **`@Services`**, перезагрузите книгу. Повторный запуск снимает соответствующую часть.

2. В настройках появится **Rooted Device Settings** — там сгенерированный пароль `root`, его можно сменить.

3. USB переключите на **«Зарядка»**, не «Связь с ПК». С компьютера (PowerShell от администратора):

   ```text
   ssh -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa root@169.254.0.1
   ```

   Логин `root`, пароль — из Rooted Device Settings. Если `169.254.0.1` молчит, IP по Wi‑Fi смотрите в Rooted Device Settings → System Status.

4. Если книга уже зависла на логотипе с воткнутым KC1 — выньте шлейф, зажмите питание ~30 с, дождитесь стола.

5. Из этой папки (рядом должны лежать `.ko`):

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install_elankc1.ps1
   ```

6. Пароль SSH спрашивается дважды. Дождитесь `[ok]  setup complete`. Книга **сама не перезагрузится**.

7. **Выключите книгу**, вставьте шлейф тача KC1, включите.

## ℹ️ Файлы

- [**`install_elankc1.ps1`**](install_elankc1.ps1) / [**`install_elankc1.sh`**](install_elankc1.sh) — поставить зонд и драйвер Elan
- [**`uninstall_elankc1.ps1`**](uninstall_elankc1.ps1) / [**`uninstall_elankc1.sh`**](uninstall_elankc1.sh) — вернуть штатный Cypress, убрать Elan. **Шлейф KC1 вынуть**
- [**`restore_factory.ps1`**](restore_factory.ps1) / [**`restore_factory.sh`**](restore_factory.sh) — заводской тач, если остались старые имена файлов. **Шлейф KC1 вынуть**
- [**`disable_cyttsp5.ps1`**](disable_cyttsp5.ps1) / [**`disable_cyttsp5.sh`**](disable_cyttsp5.sh) — спрятать стоковый Cypress с пути `cyttsp5.ko` (без установки Elan)
- [**`enable_cyttsp5.ps1`**](enable_cyttsp5.ps1) / [**`enable_cyttsp5.sh`**](enable_cyttsp5.sh) — вернуть сток на место зонда. **Шлейф KC1 вынуть**
- **`elankc1.ko`** / **`tpselect.ko`** — модули, в zip релиза лежат здесь же

## ↩️ Откат

Шлейф KC1 **вынуть**, иначе книга снова зависнет на логотипе.

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall_elankc1.ps1
```

Старые имена файлов (`.bak`, `.stock`, `elan_kc1.ko`):

```powershell
powershell -ExecutionPolicy Bypass -File .\restore_factory.ps1
```

Если всё же обновляете ПО: сначала верните родную панель с живым тачем, снимите jailbreak (`@Jailbreak` / `@Services`) и ставьте только свою линейку — на 740 `U740`, на Pro `U740-2`. Иначе апдейт может зациклиться, а без тача патч заново не накатить.

## ☑️ Частые проблемы

### Книга зависла на логотипе

Выньте шлейф тача KC1, зажмите питание примерно на 30 секунд, дождитесь стола. Потом ставьте драйвер, как выше.

### `[fail] no reply from 169.254.0.1`

USB = **«Зарядка»**, не «Связь с ПК». Jailbreak и `@Services` должны быть установлены. Иначе смотрите Wi‑Fi IP в Rooted Device Settings → System Status.

### Нет `.ko` рядом со скриптом

Берите zip со [страницы Releases](https://github.com/moss-maurice/elankc1/releases). Из этой папки в git модули не кладутся — они появляются после `make` в `build/` или в релизе.

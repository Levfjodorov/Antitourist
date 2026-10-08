# AntiTourist для Android · 0.5.1

APK уже собирается в GitHub Actions. На коммите
[`3b19872`](https://github.com/Levfjodorov/Antitourist/commit/3b19872929a0ddde1a7124cd9adf3454361bfbfe)
[запуск №12 от 8 октября 2026](https://github.com/Levfjodorov/Antitourist/actions/runs/37747134686)
завершил анализ без ошибок, выполнил 70 Flutter-тестов и собрал
`AntiTourist-0.5.1-test.apk` размером 58 850 396 байт.
Это APK в режиме release, подписанный **debug-ключом**. Установка и проверка
на физическом Android-устройстве пока не подтверждены.

## Что работает в приложении

- Поиск мест через OpenStreetMap/Overpass; отдельный режим вымышленных демо-точек.
- GPS, выбор старта на карте и определение адреса текущего местоположения.
- Пешеходные маршруты, сохранённые прогулки, избранное и история.
- Восстановление прогулки после перезапуска приложения.
- Карточки с деталями и фотографиями, когда подходящие данные доступны.
- Русский, эстонский и английский интерфейс.

Карты, поиск, маршрутизация, сведения и фотографии требуют интернета.
Приложение не запускает Python backend; его тестовый API остаётся отдельным проектом.
Демо-точки вымышленные. Доступность объектов из открытых источников требует проверки на месте.

## Сборка в GitHub Actions

Workflow **Build Android APK** автоматически проверяет pull request и изменения
в `main`. Можно также открыть Actions → Build Android APK → Run workflow.
Для тестового APK оставьте `release_signing` выключенным.

После успешного запуска скачайте artifact `AntiTourist-Android-test-<номер запуска>`.
В ZIP находятся:

| Файл | Назначение |
| --- | --- |
| `AntiTourist-0.5.1-test.apk` | APK с тестовой подписью |
| `flutter-version.json` | Точные версии Flutter, Dart и engine |
| `pubspec.lock` | Разрешённые версии и хеши зависимостей |
| `apk-metadata.json` | ID приложения, версия, разрешения и отпечаток сертификата |
| `SHA256SUMS` | Контрольная сумма APK |

Артефакты хранятся 14 дней. Workflow подготавливает SDK, проверяет Python-сценарии,
запускает анализ и Flutter-тесты, компилирует APK и проверяет пакет через
Android `apksigner` и `aapt`. PR также проверяет релизную Gradle-конфигурацию
с одноразовым тестовым ключом и проверяет переподписанный APK. Этот ключ
и переподписанный пакет не публикуются и не используются для настоящего выпуска.

Сборка фиксирует Flutter **3.47.6** в `.flutter-version`, Java **17**, Android
platform **36**, build-tools **36.0.0**, NDK **28.2.13676358** и CMake **3.22.1**.
Gradle и Android Gradle Plugin задаются шаблоном этой версии Flutter.
`mobile/pubspec.lock` взят из успешной сборки №12; `pub get --enforce-lockfile`
останавливает сборку, если версии или хеши зависимостей не совпадают.

## Локальная сборка

Потребуются Python **3.10+**, Flutter **3.47.6**, Java **17** и Android SDK.

1. Установите [Flutter](https://docs.flutter.dev/install) нужной версии и
   выполните [настройку Android](https://docs.flutter.dev/platform-integration/android/setup).
2. Выполните `flutter doctor -v`. Исправьте ошибки **Android toolchain** и
   при необходимости примите лицензии через `flutter doctor --android-licenses`.
3. Укажите `ANDROID_HOME` или `ANDROID_SDK_ROOT`, чтобы сценарий нашёл
   `apksigner` и `aapt` в Android build-tools.
4. В корне репозитория запустите `Build-APK.cmd` на Windows либо команду ниже.

Windows:

```powershell
py -3 scripts/build_android.py
```

Linux/macOS:

```bash
python3 scripts/build_android.py
```

Исходники находятся в `mobile`. Сценарий каждый раз пересоздаёт временный
Android-проект в `build/android-project`, добавляет INTERNET и разрешения
геолокации, сохраняет минимальную версию Android **7.0 / API 24** и генерирует иконки.
Локальный debug-ключ Flutter хранится вне этого проекта, обычно в `~/.android`.
Изменения следует вносить в `mobile` или сценарий сборки; сгенерированные файлы
при следующем запуске будут заменены.

Обновляйте зависимости явно, используя зафиксированный Flutter SDK:

```bash
cd mobile
flutter pub upgrade
```

Закоммитьте изменения `pubspec.yaml` и `pubspec.lock` вместе и проверьте Actions.
При смене Flutter обновите `.flutter-version` и согласуйте SDK-пакеты workflow
с новым шаблоном. Сценарий отклоняет незнакомый Gradle-шаблон вместо пропуска
настройки минимального SDK или подписи.

## APK с постоянной релизной подписью

Тестовый workflow создаёт debug-ключ на новом runner. Подписи разных запусков
могут различаться, поэтому такие APK не подходят для надёжного обновления приложения.
Для выпусков используйте один постоянный keystore и сохраняйте его резервную копию.

Если ключа ещё нет, создайте его локально; `keytool` запросит пароли:

```bash
keytool -genkeypair -v -keystore antitourist-release.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias antitourist
```

В Settings → Secrets and variables → Actions добавьте **repository secrets**:

| Secret | Значение |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Keystore, закодированный в Base64 без переносов строк |
| `ANDROID_STORE_PASSWORD` | Пароль keystore |
| `ANDROID_KEY_ALIAS` | Алиас ключа, например `antitourist` |
| `ANDROID_KEY_PASSWORD` | Пароль ключа |

На Windows можно скопировать Base64 в буфер обмена:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path .\antitourist-release.jks).Path)) | Set-Clipboard
```

На Linux: `base64 -w 0 antitourist-release.jks`; на macOS:
`base64 -i antitourist-release.jks | tr -d '\n'`.
Храните ключ и пароли вне репозитория; `.gitignore` исключает keystore и
локальные файлы с настройками подписи.

После объединения исправлений запустите workflow **из `main`** и включите
`release_signing`. При отсутствии любого секрета сборка завершится ошибкой.
Выход: `AntiTourist-Android-release-<номер запуска>` с файлом
`AntiTourist-0.5.1-release.apk`. Workflow не создаёт GitHub Release автоматически.
Временный keystore удаляется после работы; APK проверяется на соответствие
сертификату выбранного ключа. Переключение на debug-ключ при ошибке запрещено.

Для локальной релизной сборки задайте переменные окружения
`ANDROID_KEYSTORE_PATH`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
`ANDROID_KEY_PASSWORD` и выполните:

```bash
python3 scripts/build_android.py --release-signing
```

Пароли передаются Gradle и keytool через окружение. Они не записываются в
сгенерированный Gradle-файл, аргументы команд или артефакт.
Текущая версия приложения — **0.5.1+9**. Перед следующим выпуском увеличьте
число после `+`: Android требует больший `versionCode` для обновления.
Для Google Play отдельно потребуется AAB и настройка Play App Signing;
этот workflow выпускает APK для непосредственной установки.

## Проверка на телефоне перед выпуском

Скопируйте APK на телефон и разрешите установку из выбранного источника либо
используйте `adb install -r dist/AntiTourist-0.5.1-release.apk`.
Обновление возможно при том же ID приложения, том же сертификате и подходящем
`versionCode`. Переход с прежнего debug-APK на постоянный ключ потребует удаления
тестовой версии; удаление также удаляет её локальные прогулки, избранное и историю.

Проверьте на устройстве:

- Запуск, иконку, три языка интерфейса и работу на узком экране.
- GPS: точные и приблизительные координаты, отказ в разрешении, отключённую геолокацию.
- Поиск, карту, маршрут, сведения и фотографии при доступной и недоступной сети.
- Сохранение прогулки, избранного и истории после принудительного завершения приложения.
- Установку следующего APK поверх предыдущего выпуска с тем же постоянным ключом.

Успешная компиляция и widget-тесты не заменяют проверку Android-плагинов на устройстве.
Официальная инструкция: [Build and release an Android app](https://docs.flutter.dev/deployment/android).

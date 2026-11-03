# Тесты SDK внутри iOS-приложения

Проект `SDKTestHost.xcodeproj` запускает push-тесты, которым нужен процесс iOS-приложения для работы с `UNUserNotificationCenter`.
В тестовую цель явно подключены существующие файлы из `../Tests`:

- `PushServiceTests/PushAutomaticRegistrationTests.swift` — автоматическая регистрация токена и управление категориями.
- `PushServiceTests/PushRetryTestStorage.swift` — вспомогательное хранилище для изоляции тестов.
- `PushNotificationExtensionTests/PushNotificationExtensionTests.swift` — обработка уведомлений, включая регистрацию категорий с кнопками.

Новые тестовые файлы, требующие приложения, нужно добавлять в цель `SDKHostedTests`.

Запуск из корня репозитория:

```sh
xcodebuild test \
  -project TestHost/SDKTestHost.xcodeproj \
  -scheme SDKHostedTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO
```

Требуются Xcode 16 или новее и установленный симулятор из параметра `destination`.
Тесты выполняются последовательно, поскольку используют общие настройки SDK и системные категории уведомлений.
Обычный запуск схемы пакета `ConsultantSdk-Package` сохраняется; сценарии, требующие приложения, в нём пропускаются.

В CI задача `Tests / TestHost` собирает приложение и запускает его тесты на симуляторе.
Обычные тесты модулей выполняются в отдельных задачах `Tests / <модуль>`.
Логи и результат запуска хостовых тестов сохраняются в артефакте `tests-TestHost`.

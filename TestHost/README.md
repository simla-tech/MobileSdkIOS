# Тесты SDK внутри iOS-приложения

Проект `SDKTestHost.xcodeproj` запускает все Swift-тесты из `../Tests` внутри минимального приложения.
Файлы тестов подключаются автоматически через синхронизированную группу Xcode.
Приложение требуется для `UNUserNotificationCenter` и тестов автоматической регистрации push.

Запуск из корня репозитория:

```sh
xcodebuild test \
  -project sdk/TestHost/SDKTestHost.xcodeproj \
  -scheme SDKHostedTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO
```

Требуются Xcode 16 или новее и установленный симулятор из параметра `destination`.
Тесты выполняются последовательно, поскольку используют общие настройки Firebase и SDK.
Обычный запуск схемы пакета `ConsultantSdk-Package` сохраняется; 14 сценариев, требующих приложения, в нём пропускаются.

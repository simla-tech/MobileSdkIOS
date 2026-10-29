# Онлайн-консультант

Модуль `OnlineConsultant` добавляет готовый экран чата для общения клиента с менеджерами CRM-системы зарегистрированной в RetailCRM.
Экран доступен для UIKit и SwiftUI.

## Оглавление

- [Подключение](#подключение)
- [Идентификация клиента](#идентификация-клиента)
- [UIKit](#uikit)
- [SwiftUI](#swiftui)
- [Публичные методы и свойства](#публичные-методы-и-свойства)
- [События в реальном времени](#события-в-реальном-времени)
- [Локализация](#локализация)
- [Возможности чата](#возможности-чата)
- [Публичные ошибки](#публичные-ошибки)

## Подключение

Передайте настройки чата при инициализации SDK:

```swift
CrmSdk.initialize(
    config: CrmSdkConfig(
        siteToken: "<site-token>",
        consultantConfig: OnlineConsultantConfig(
            connectTimeout: 30,
            autoReconnectWebSocket: true,
            webSocketReconnectDelay: 3,
            messagesPageSize: 50,
            initialMessagesLimit: 50,
            cachePolicy: OnlineConsultantCachePolicy(
                maxDiskSizeBytes: nil,
                maxFileAge: nil,
                automaticCleanup: true
            )
        )
    )
) { result in
    if case let .failure(error) = result { print(error) }
}
```

### Настройка `OnlineConsultantConfig`

- `connectTimeout` — таймаут открытия WebSocket, в секундах. По умолчанию `30`.
- `autoReconnectWebSocket` — повторное подключение WebSocket после ошибки. По умолчанию `true`.
- `webSocketReconnectDelay` — задержка перед повторным подключением, в секундах. По умолчанию `3`.
- `messagesPageSize` — размер страницы истории сообщений; диапазон при запросе `1...1000`. По умолчанию `50`.
- `initialMessagesLimit` — целевое число сообщений после первого подключения; диапазон `0...1000`. По умолчанию `50`.
- `cachePolicy` — правила очистки кеша файлов и изображений. По умолчанию `OnlineConsultantCachePolicy()`.

### Настройка `OnlineConsultantCachePolicy`

- `maxDiskSizeBytes: Int64?` — предельный размер кеша в байтах; `nil` отключает ограничение.
- `maxFileAge: TimeInterval?` — предельный возраст файла в секундах; `nil` отключает ограничение.
- `automaticCleanup: Bool` — применяет правила очистки после сохранения или загрузки файла; по умолчанию `true`. Если оба ограничения равны `nil`, файлы не удаляются по размеру или возрасту. Если `false`, очистку нужно запускать через `trimCache()` или `clearCache()` либо их варианты с `completion`.

Если `consultantConfig` не передан, используется `OnlineConsultantConfig()` с `connectTimeout` по умолчанию 30 секунд.

## Идентификация клиента

Приложение должно сообщать SDK о входе, смене аккаунта и выходе клиента через `CrmSdk.shared.setCustomerIdentity(_:)`.
Для привязки чата к клиенту CRM передайте `siteCustomerId` и `siteCode`.
Одного внутреннего `customerId` для привязки чата недостаточно.
SDK не отслеживает авторизацию в приложении самостоятельно.
Подробнее — в разделе [«Идентификация клиента»](./sdk.md#идентификация-клиента).

При передаче нового идентификатора SDK отключает текущую сессию и автоматически подключает
сессию указанного клиента. Отдельно переподключать чат не требуется.

При выходе из аккаунта вызовите `sdk.setCustomerIdentity(nil)`: этот вызов сообщает SDK о выходе
и переключает сессию на анонимного пользователя.

## UIKit

Экран использует модуль `CrmSdk.shared.onlineConsultant`.
Дополнительный вызов для запуска чата не требуется.
Для отображения заголовка чата рекомендуется обернуть его в `UINavigationController`

```swift
import OnlineConsultant
import UIKit
import Core

func configureOnlineConsultantChat() -> UINavigationController {
    let chatVC = OnlineConsultantViewController()
    let nvChat = UINavigationController(rootViewController: chatVC)
    
    CrmSdk.shared.onlineConsultant.onUnreadIncomingMessagesCountChange = { count in
        // update badge
    }
    CrmSdk.shared.onlineConsultant.onStateChange = { state in
        // update visibility
    }
    return nvChat
}
```
SDK поддерживает анонимный чат: после подключения без `customerIdentity` контроллер возвращает `.ready(isAnonymous: true)`. Значение `false` означает, что identity задана, но не подтверждает привязку к карточке клиента CRM.
Пример ограничения чата только сессиями с заданной identity:

```swift
CrmSdk.shared.onlineConsultant.onStateChange = { [weak self] state in
    if case .ready(isAnonymous: false) = state {
        self?.chatTabBarItem.isEnabled = true
    } else {
        self?.chatTabBarItem.isEnabled = false
    }
}
```

## SwiftUI

Для заголовка и бейджа в SwiftUI создайте `OnlineConsultantObserver` и храните его как `@StateObject`:

```swift
import Core
import OnlineConsultant
import SwiftUI

@MainActor
struct ChatTabView: View {
    @StateObject private var consultant = OnlineConsultantObserver(
        onlineConsultant: CrmSdk.shared.onlineConsultant
    )

    var body: some View {
        TabView {
            OnlineConsultantScreen()
                .tabItem {
                    Label(consultant.name ?? "Чат", systemImage: "bubble.left")
                }
                .badge(consultant.unreadIncomingMessagesCount)
        }
    }
}
```

## Публичные методы и свойства

`CrmSdk.shared.onlineConsultant` возвращает `OnlineConsultantController`. Его публичные методы:

- `cacheStatistics() -> ConsultantCacheStatistics` — возвращает число файлов и размер локального кеша в байтах.
- `trimCache() async throws -> ConsultantCacheStatistics` и вариант с `completion` — применяет `cachePolicy`.
- `clearCache() async throws` и вариант с `completion` — удаляет файлы из локального кеша SDK.
- `onStateChange: ((ControllerState) -> Void)?`
- `onUnreadIncomingMessagesCountChange: ((Int) -> Void)?`

Доступные для чтения свойства контроллера:

- `state: ControllerState` — текущее состояние чата:
  - `.idle` — чат не активен и не выполняет подключение;
  - `.connecting` — чат устанавливает соединение с сервером;
  - `.ready(isAnonymous: Bool)` — чат подключён; `isAnonymous` показывает, что сессия создана без `customerIdentity`;
  - `.failed(ConsultantError)` — подключение завершилось ошибкой; причины сгруппированы в `.client`, `.controller`, `.fileCache` и `.attachment`.
- `unreadIncomingMessagesCount: Int` — количество непрочитанных входящих сообщений среди загруженных; `0`, если счётчик отключён конфигурацией.
- `name: String?` — название чата из конфигурации сервера.
- `linkSettings: LinkSettings` — настройки ссылок из конфигурации сервера: `links`, `linksMode`, `linksOrientation`, `alwaysShowLinksOnDesktops`.

Все публичные методы и переменные `OnlineConsultantController` доступны через `OnlineConsultantObserver` для использования в SwiftUI.

## События в реальном времени

При инициализации онлайн-консультанта SDK автоматически подписывается на события через WebSocket.
Благодаря этому новые сообщения и изменения состояния чата отображаются без дополнительных
действий со стороны приложения.

Подписка учитывает жизненный цикл приложения: при переходе в фоновый режим SDK отключается от
WebSocket, а после возвращения приложения на передний план автоматически подключается и
подписывается на события повторно.
В приложении с несколькими окнами соединение сохраняется, пока хотя бы одно окно находится на переднем плане.
Временная потеря активности без перехода в фон не закрывает соединение.
Если сессия подключена в фоне, открытие WebSocket откладывается до возвращения приложения.

Восстановление после фона не зависит от `autoReconnectWebSocket` и выполняется без задержки
`webSocketReconnectDelay`; эти настройки управляют повторными попытками после ошибок на переднем плане.
После отключения сессии возврат приложения на передний план не открывает WebSocket до нового подключения.

## Локализация

SDK содержит русский, английский и испанский переводы. Язык выбирается стандартным механизмом iOS
с учётом языковых настроек приложения и доступных локализаций SDK. Язык по умолчанию — русский.

## Возможности чата

Экран автоматически загружает историю, получает новые сообщения и отправляет текст.
Кнопка вложения открывает системный выбор файлов и фото и позволяет отправить несколько файлов.

Готовый интерфейс поддерживает:

- текстовые сообщения, ссылки и цитаты;
- изображения и файловые вложения;
- карточки товаров и заказов;
- быстрые ответы;
- формы сбора контактных данных;
- форму обращения, когда консультант находится офлайн;
- отображение состояния отправки сообщений;
- повторную отправку неотправленных текстов, файлов и изображений через пункт «Повторить отправку» в контекстном меню сообщения;
- загрузку более ранних сообщений при прокрутке истории.

Контактные формы, режим офлайн и оформление чата применяются по настройкам онлайн-консультанта,
полученным от сервера.

SDK автоматически поддерживает WebSocket-соединение, пока приложение находится на переднем плане,
и восстанавливает его после возвращения из фона.

## Публичные ошибки

Публичные ошибки реализуют `LocalizedError`.
Сообщения фиксированных состояний доступны на русском, английском и испанском языках.
Диагностические подробности и сообщения сервера могут быть на языке источника.

Публичная ошибка модуля `OnlineConsultant` — `ConsultantError`.
Методы `trimCache` и `clearCache` выбрасывают её в вариантах `async throws` или передают в `completion`.
Ошибка подключения приходит в `ControllerState.failed(ConsultantError)`; изменения состояния доступны через `onStateChange`.
Для получения текста ошибки используйте `localizedDescription`, для определения причины — соответствующий вариант `ConsultantError` и вложенного типа `Failure`.

### Ошибки сетевого клиента — `client(ClientFailure)`

- `client(.missingConnectionCredentials)` — в ответе подключения отсутствует токен пользователя или идентификатор сессии. SDK не может использовать такое подключение для запросов чата.
- `client(.httpStatus(Int, [String]))` — сервер вернул HTTP-статус ошибки. Первое значение — код статуса, второе — сообщения сервера; массив сообщений может быть пустым.
- `client(.requestFailed(String))` — не удалось выполнить запрос или получить корректно разобранный ответ. Причиной может быть ошибка сети, кодирования запроса или декодирования ответа; строка содержит подробности.

### Ошибки состояния чата — `controller(ControllerFailure)`

- `controller(.notConnected)` — операция требует подключённой сессии, но у контроллера нет токена пользователя или идентификатора сессии. Возникает при попытке выполнить операцию до подключения или после сброса сессии.
- `controller(.missingCredentials)` — при применении данных подключения не найден токен пользователя или идентификатор сессии. В отличие от `notConnected`, ошибка относится к полученным данным подключения.
- `controller(.unavailable)` — сервер вернул `behaviour.widget = false`: онлайн-консультант недоступен для этого подключения. Это не признак отсутствия менеджеров онлайн; офлайн-режим чата обрабатывается отдельно.
- `controller(.missingUploadedFileID)` — сервер ответил на загрузку вложения без идентификатора файла. SDK не может добавить такой файл в отправляемое сообщение.
- `controller(.inputAttachmentsNotReady)` — при подготовке сообщения у одного из вложений ещё нет идентификатора загруженного файла. Перед отправкой все вложения должны успешно загрузиться; незагруженные вложения нужно загрузить повторно или удалить.

### Ошибки кеша файлов — `fileCache(FileCacheFailure)`

- `fileCache(.emptyFileID)` — для сохранения файла или обновления его данных передан пустой идентификатор, в том числе строка из пробелов.
- `fileCache(.missingEntry(fileID: String))` — при обновлении удалённого URL файла в кеше не найдена запись с указанным идентификатором. `fileID` содержит идентификатор отсутствующей записи.
- `fileCache(.operationFailed(String))` — другая ошибка операции с кешем, например создания каталога, записи файла, сохранения списка записей или удаления данных. Строка содержит описание исходной ошибки.

### Ошибки вложений — `attachment(AttachmentFailure)`

- `attachment(.emptyImageData)` — не удалось получить данные выбранного изображения для загрузки.
- `attachment(.imageTooLarge)` — размер изображения превышает лимит `3 × 1024 × 1024` байт. Для загрузки нужно выбрать или подготовить изображение меньшего размера.
- `attachment(.fileTooLarge)` — размер выбранного документа превышает лимит `5 × 1024 × 1024` байт.
- `attachment(.tooManyAttachments)` — превышен лимит в 10 вложений в поле ввода. Удалите часть вложений перед добавлением новых.
- `attachment(.operationFailed(String))` — другая ошибка операции с вложением; строка содержит описание причины.

### Другие ошибки — `unexpected(String)`

- `unexpected(String)` — ошибка, для которой нет отдельного варианта `ConsultantError`; строка содержит описание исходной причины. В этот вариант также преобразуются ошибки кодирования и декодирования публичных `Codable`-моделей ссылок чата.

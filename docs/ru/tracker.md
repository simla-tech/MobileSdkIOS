# Трекер

Модуль `tracker` передаёт в RetailCRM события из приложения: просмотры экранов и товаров,
нажатия, регистрацию и вход клиента, изменения корзины и оформление заказа.

## Оглавление

- [Подключение](#подключение)
- [Идентификация клиента](#идентификация-клиента)
- [Публичные методы и свойства](#публичные-методы-и-свойства)
- [Настраиваемые события](#настраиваемые-события)
- [Очередь и доставка](#очередь-и-доставка)
- [Диагностика](#диагностика)
- [Публичные ошибки](#публичные-ошибки)

## Подключение

Передайте настройки при инициализации SDK. Трекер создаётся при первом обращении к
`CrmSdk.shared.tracker` и автоматически готовит локальную очередь после подключения общей сессии.
Вызывайте `configureTracker()` сразу после `CrmSdk.initialize(...)`.
Назначьте `onReadyUpdate`, чтобы получить флаг необходимости формы согласия и ошибку подготовки.
Обработчик вызывается на главном потоке; поздний подписчик получает актуальный результат.
Если форма необходима, покажите её и передайте решение через `setConsent(_:)`.
SDK не хранит решение между запусками. Восстановите сохранённое согласие через `setConsent(_:)`
перед назначением обработчика, чтобы не показывать форму повторно.

```swift

import Core
import Tracker

CrmSdk.initialize(
    config: CrmSdkConfig(
        siteToken: "<site-token>",
        trackerConfig: TrackerConfig(
            batchSize: 50,
            flushInterval: 15,
            timeSyncInterval: 60 * 60
        )
    )
) { result in
    if case .failure(let error) = result {
        print(error.localizedDescription)
    }
}
configureTracker()

private func configureTracker() {
    let tracker = CrmSdk.shared.tracker
    if let savedConsent = UserDefaults.standard.string(forKey: "trackerConsentKey") {
        tracker.setConsent(savedConsent == "granted" ? .granted : .denied)
    }
    tracker.onReadyUpdate = { needShowForm, error in
        if let error {
            print(error.localizedDescription)
        } else if needShowForm {
            // Покажите форму согласия и передайте решение через setConsent(_:).
        }
    }
}
```

### Настройка `TrackerConfig`

Передайте `TrackerConfig` в `CrmSdkConfig(trackerConfig:)`, если нужны значения, отличные от стандартных:

- `batchSize` — максимальное число событий в пачке, от 1 до 50; по умолчанию 50.
- `flushInterval` — интервал отправки в секундах, от 0 до 86 400; по умолчанию 15. Значение 0 отключает периодическую отправку.
- `timeSyncInterval` — интервал синхронизации времени с сервером в секундах, от 0 до 86 400; по умолчанию 3600.

## Идентификация клиента

Сообщайте SDK о входе, смене аккаунта и выходе клиента через `CrmSdk.shared.setCustomerIdentity(...)`.
Подробнее — в разделе [«Идентификация клиента»](./sdk.md#идентификация-клиента).

## Публичные методы и свойства

`CrmSdk.shared.tracker` возвращает `Tracker`.

- `onReadyUpdate: ((Bool, TrackerError?) -> Void)?` — сообщает на главном потоке результат автоматической подготовки. Флаг равен `true`, только если требуется согласие, а решение равно `.unknown`; при ошибке передаётся `false` и `TrackerError`. Поздний подписчик получает актуальный результат. Изменение согласия обновляет флаг; при переподключении предыдущий результат сбрасывается до новой подготовки. При ожидании подключения без ошибки обработчик не вызывается. Передаются ошибки общей сессии и локальной очереди. Готовность не означает согласие на трекинг или доставку событий; трекинг может быть отключён на сайте. Присвоение `nil` отключает подписку.
- `consentState: TrackerConsentState` — текущее решение: `.unknown`, `.granted` или `.denied`.
- `onEventUpdate: ((TrackerEventUpdate) -> Void)?` — сообщает ID событий при постановке в очередь, отправке, доставке, повторной попытке, отклонении и удалении. Может вызываться вне главного потока.
- `setConsent(_:) -> Result<Void, TrackerError>` — применяет решение пользователя и при отказе очищает очередь.
- `flushAll() async throws` и `flushAll(completion:)` — пытаются отправить все события из текущей очереди. При частичной отправке возвращают `.flushIncomplete([String])` с ID неотправленных событий.

Все методы `track*` доступны в вариантах `async throws -> String` и с `completion`. Вариант с `completion` возвращается сразу и вызывает обработчик на главном потоке с `Result<String, TrackerError>`. Успешный результат содержит ID события, принятого в стартовый буфер или записанного в очередь, а не подтверждение доставки сервером. Удаление принятых событий сообщается через `onEventUpdate.dropped`.

- `trackPageView(screenURI:title:product:code:completion:)` — `page_view`; задаёт текущую страницу и адрес предыдущей страницы для следующих событий. `screenURI` должен быть абсолютным URI. `TrackerViewedProduct` принимает ID предложения, внутренний или внешний ID товара и бренд.
- `trackClick(element:leaving:code:completion:)` — `click`; клик по элементу.
- `trackRegister(customer:createCustomer:createCustomerByEmail:code:completion:)` — `register`; данные клиента и подписки. `createCustomer` по умолчанию `false`. Для запроса создания клиента в CRM установите его в `true`; создание по email дополнительно требует `createCustomerByEmail: true` и email клиента. Успешная запись события регистрации в очередь не подтверждает создание клиента в CRM.
- `trackLogin(customerEmail:subscriptions:code:completion:)` — `login`; вход клиента.
- `trackConsult(customerEmail:subscriptions:code:completion:)` — `consult`; попытка связаться с консультантом.
- `trackOpenCart(customerEmail:code:completion:)` — `open_cart`; открытие корзины.
- `trackContact(channel:code:completion:)` — `contact`; запрос связи через Telegram или WhatsApp.
- `trackCart(cartID:items:code:completion:)` — `cart`; изменение состава корзины.
- `trackOrder(identifier:cartID:items:deliveryPrice:total:code:completion:)` — `order`; оформление заказа. `identifier`: `.systemID(Int64)` — внутренний ID заказа CRM (`order_id`), `.externalID(String)` — внешний ID (`order_external_id`), `.number(String)` — номер (`order_number`).
- `trackSubscription(_:code:completion:)` — `subscription`; изменение подписки.
- `trackFormStart(formSelector:code:completion:)` — `form_start`; начало заполнения формы.
- `trackFormSubmit(formSelector:code:completion:)` — `form_submit`; отправка формы.
- `trackFileDownload(fileName:element:code:completion:)` — `file_download`; скачивание файла.
- `trackFavoriteProduct(offer:removed:code:completion:)` — `favorite_product`; добавление предложения в избранное или удаление из него.

При нажатии на push-уведомление или его кнопку SDK запоминает UTM-метки и автоматически добавляет их в последующие события `order`. Новый push с метками заменяет набор; push без меток его не очищает. Активный набор хранится до завершения процесса приложения. Созданные события сохраняют собственные метки в SQLite и передают их при повторной отправке, включая отправку после перезапуска. Поле `utm_term` из push передаётся как `utm_keyword` внутри `utm`.

## Настраиваемые события

Все методы `track*()` принимают необязательный параметр `code`. Его значение берётся
из настроек события в административной панели RetailCRM.

## Очередь и доставка

Успешный вызов `track*` подтверждает принятие события в стартовый буфер или очередь SQLite, но не доставку на сервер.
Результаты отправки доступны через `onEventUpdate`.

### Стартовый буфер

До готовности трекера события могут сохраняться в памяти при согласии `.unknown` или `.granted`.
Буфер вмещает до 1000 событий; при переполнении удаляются самые старые.
Он сохраняет ID, время, порядок и контекст событий.

После подготовки SQLite события переносятся в постоянную очередь, если сервер разрешает трекинг
и выполнены требования к согласию. Если трекинг отключён или обязательное согласие ещё не получено,
буфер очищается. Отказ в согласии, отключение сессии и смена пользователя также очищают буфер.
До переноса в SQLite события теряются при завершении приложения.

### Постоянная очередь

SQLite хранит одну очередь до 1000 событий с владельцем `siteToken` + `userToken`.
При переполнении удаляются самые старые события; при объединении восстановленной очереди со стартовым
буфером также сохраняются только последние 1000 событий.
При перезапуске с тем же владельцем очередь восстанавливается, если трекинг и согласие разрешают её использование.
При смене владельца прежние данные удаляются.
При смене `customerIdentity`, включая выход, обычные и слишком большие события удаляются до переподключения.
При открытии базы от прежней версии SDK сохраняются только данные текущего владельца с теми же ограничениями.

### Отправка и повторные попытки

SDK автоматически пытается отправить один пакет после подготовки очереди при подключении,
при накоплении `batchSize` событий и с интервалом `flushInterval`.
Значение `flushInterval = 0` отключает периодическую отправку.

Пачки формируются из целых событий с учётом `batchSize` и размера JSON: целевой размер —
на 1 КиБ меньше лимита 1 МиБ (`1 048 576` байт). Одно событие не делится на части.
Если запрос с одним событием превышает лимит, SDK отклоняет его до отправки с ошибкой `eventTooLarge`.
При HTTP 413 для пачки SDK повторяет отправку событий по одному.
HTTP 413 для одного события также приводит к его отклонению.
Такие события исключаются из обычной очереди и не отправляются повторно: отдельно сохраняются последние 50,
при добавлении новых самые старые удаляются.

Доставленные и окончательно отклонённые сервером события удаляются из очереди.
События с временными ошибками остаются для следующих попыток отправки.
При HTTP 429 SDK учитывает `Retry-After`; ручная отправка это ограничение не обходит.

### Принудительная отправка

`flushAll()` пытается отправить все события, находившиеся в постоянной очереди на момент вызова,
несколькими пакетами. Новые события и стартовый буфер в эту попытку не входят.
Метод учитывает готовность подключения, согласие и ограничения сервера.
Если не все события доставлены, возвращается ошибка `flushIncomplete([String])` с их ID;
в неё также включаются ID сохранённых слишком больших событий.
При отсутствии подключения, согласия или при ограничении частоты запросов метод может вернуть соответствующую ошибку.

```swift
do {
    try await CrmSdk.shared.tracker.flushAll()
} catch {
    print(error.localizedDescription)
}
```

После переподключения SDK автоматически возобновляет обработку очереди.
Если нужно попытаться доставить накопленные события перед сменой клиента или выходом,
вызовите `flushAll()` и дождитесь результата до `setCustomerIdentity(_:)`:
при смене клиента оставшиеся события удаляются.

## Диагностика 

Для наблюдения за отправкой событий используйте `onEventUpdate`:

```swift
import Core
import Tracker

Task { @MainActor in
    CrmSdk.shared.tracker.onEventUpdate = { event in
        switch event {
        case .queued(let ids):
            // События добавлены в очередь     
            print("CrmSdk.shared.tracker.onEventUpdate queued = \(ids)")
        case .sending(let ids, let payload):
            // Начинается попытка отправки пакета
            print("CrmSdk.shared.tracker.onEventUpdate sending = \(ids), payload = \(payload)")
        case .delivered(let ids):
            // Сервер принял события  
            print("CrmSdk.shared.tracker.onEventUpdate delivered = \(ids)")
        case .retryScheduled(let ids, let error):
            // События оставлены для повторной отправки
            print("CrmSdk.shared.tracker.onEventUpdate retryScheduled = \(ids), error = \(error)")
        case .rejected(let id, let error):
            // Событие окончательно отклонено сервером       
            print("CrmSdk.shared.tracker.onEventUpdate rejected = \(id), error = \(error)")
        case .dropped(let ids, let reason):
            // События удалены при очистке или переполнении очереди  
            print("CrmSdk.shared.tracker.onEventUpdate dropped = \(ids), reason = \(reason)")
        }
    }
}
```

## Публичные ошибки

Публичные ошибки реализуют `LocalizedError`.
Сообщения фиксированных состояний доступны на русском, английском и испанском языках.
Диагностические подробности и сообщения сервера могут быть на языке источника.

Публичная ошибка модуля `Tracker` - `TrackerError`

Ошибки подготовки передаются через `onReadyUpdate`. Методы `track*` и `flushAll` передают `TrackerError` через `throw` или `completion`, а `setConsent(_:)` возвращает его в `Result`. `onEventUpdate` использует этот же тип для ошибок событий.
Описания ошибок и причины, сформированные SDK, локализованы на русский, английский и испанский языки. Подробности системных ошибок и ответы сервера сохраняют язык источника.

- `invalidEvent(String)` — некорректные параметры события.
- `eventTooLarge(sizeBytes:limitBytes:)` — SDK отклонил событие до отправки: размер JSON-запроса превышает локальный лимит.
- `unavailable`, `consentRequired`, `missingConnection` — отправка недоступна, требуется согласие или нет подключения.
- `storage(String)` — ошибка локальной очереди.
- `requestEncodingFailed(String)`, `requestFailed(String)`, `invalidResponse(String)` — ошибка запроса или ответа.
- `httpStatus(Int, [String], retryAfter: TimeInterval?)` — HTTP-статус, сообщения сервера и интервал повторной попытки.
- `eventRejected(String)` — сервер отклонил отдельное событие.
- `flushIncomplete([String])` — после `flushAll` не все события отправлены; массив содержит их ID.

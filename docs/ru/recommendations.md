# Товарные рекомендации

Модуль `recommendations` получает товарные рекомендации RetailCRM и передаёт события показа блока и нажатия на товар. Отображение товаров и переходы реализует приложение.

## Оглавление

- [Подключение](#подключение)
- [Идентификация клиента](#идентификация-клиента)
- [Получение рекомендаций](#получение-рекомендаций)
- [Учёт взаимодействий](#учёт-взаимодействий)
- [Публичные методы и свойства](#публичные-методы-и-свойства)
- [Публичные ошибки](#публичные-ошибки)

## Подключение

Модуль использует общее подключение `CrmSdk`, а для отправки событий — общий `Tracker`.
Для получения товаров нужна активная механика рекомендаций в RetailCRM.
Отдельного `RecommendationsConfig` нет. См. [«Настройка трекера»](./tracker.md#подключение).
Общий трекер подготавливается автоматически после подключения общей сессии.
Назначьте `onReadyUpdate`, чтобы получить флаг необходимости формы согласия и ошибку подготовки.
Настройку можно выполнить сразу после вызова `CrmSdk.initialize`.
Согласие общее с `Tracker`: приложение сохраняет решение и восстанавливает его через `setConsent(_:)` перед назначением обработчика.
Если согласие уже восстановлено через `Tracker`, повторять это не требуется.

```swift
import Core
import Recommendations

private func configureConsultant() {
    CrmSdk.initialize(
        config: .init(
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
    configureRecommendations()
}

private func configureRecommendations() {
    let recommendations = CrmSdk.shared.recommendations

    if let savedConsent = UserDefaults.standard.string(forKey: "trackerConsentKey") {
        _ = recommendations.setConsent(savedConsent == "granted" ? .granted : .denied)
    }

    recommendations.onReadyUpdate = { needShowForm, error in
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

## Получение рекомендаций

Для получения товаров нужна активная механика рекомендаций в RetailCRM. Требования к данным клиента и товара определяются настройками механики.
SDK автоматически использует идентификатор клиента, переданный через `setCustomerIdentity(_:)`.
При наличии обоих идентификаторов используется `customerId`, иначе — `siteCustomerId`. После `setCustomerIdentity(nil)` идентификаторы клиента в запрос не добавляются.
Подробнее — в разделе [«Идентификация клиента»](./sdk.md#идентификация-клиента).

```swift
let request = ProductRecommendationsRequest(
    mechanicCode: "mobile-home",
    blockCode: "product_similar",
    productID: 101
)

CrmSdk.shared.recommendations.getProducts(request) { result in
    switch result {
    case .success(let selection):
        // Отобразите selection.products, затем вызовите didDisplayRecommendations(selection).
    case .failure(let error):
        print(error.localizedDescription)
    }
}
```

Приложение само отображает карточки и выполняет переходы.
Метод `getProducts` работает без ожидания подготовки трекера и согласия на трекинг: запрос товаров не проверяет готовность трекера и не записывает показ.

## Учёт взаимодействий

### Показ блока

После отображения блока вызовите `trackImpression(_:)`:

```swift
private func didDisplayRecommendations(_ selection: ProductRecommendations) {
    CrmSdk.shared.recommendations.trackImpression(
        selection, screenURI: "app://products/101", title: "Карточка товара"
    ) { result in
        if case .failure(let error) = result {
            print(error.localizedDescription)
        }
    }
}
```

### Нажатие на товар

При выборе рекомендованного товара вызовите `trackClick(_:)`:

```swift
private func didSelectRecommendation(
    _ product: RecommendedProduct,
    position: Int,
    from selection: ProductRecommendations
) {
    CrmSdk.shared.recommendations.trackClick(
        selection, productID: product.productID, position: position
    ) { result in
        if case .failure(let error) = result {
            print(error.localizedDescription)
        }
    }
}
```

## Публичные методы и свойства

`CrmSdk.shared.recommendations` возвращает `Recommendations`.

Все варианты методов с `completion` вызывают обработчик на главном потоке.

- `onReadyUpdate: ((Bool, TrackerError?) -> Void)?` — сообщает на главном потоке результат автоматической подготовки общего трекера. Флаг равен `true`, только если сайт требует согласия, а решение равно `.unknown`; при ошибке передаётся `false` и `TrackerError`. Поздний подписчик получает актуальный результат. Изменение согласия обновляет флаг. При переподключении старый результат сбрасывается. До подключения обработчик не вызывается, кроме ошибки соединения. Обработчик общий с `Tracker.onReadyUpdate`: назначение через один модуль заменяет обработчик другого, `nil` отключает общий обработчик. Готовность не означает разрешение на сбор или доставку событий.
- `consentState: TrackerConsentState` — текущее решение: `.unknown`, `.granted` или `.denied`.
- `setConsent(_ consent: RecommendationsConsentState) -> Result<Void, RecommendationsError>` — применяет решение пользователя к общему трекеру; при отказе очищает очередь событий.
- `getProducts(_:) async throws -> ProductRecommendations` и `getProducts(_:completion:)` — загружают подборку по `ProductRecommendationsRequest`. `mechanicCode` — обязательный непустой символьный код механики. Код передаётся без изменений, его формат проверяет сервер. `blockCode` — непустой код места показа. Пустая подборка считается успешным результатом.

  Метод `getProducts` возвращает `ProductRecommendations`:

  - `executionID` (`UInt64`) — Идентификатор выполнения механики, используемый для учёта показов и нажатий.
  - `personalized` (`Bool`) — Признак персонализированной подборки.
  - `context` (`ProductRecommendationContext`) — Контекст выполнения механики.
  - `productIds` (`[Int64]`) — Идентификаторы рекомендованных товаров с доступными торговыми предложениями.
  - `products` (`[RecommendedProduct]`) — Доступные рекомендованные торговые предложения.

  Поля `ProductRecommendationContext`:

  - `mechanicType` (`String`) — Тип механики, например `personal` или `similar`.
  - `required` (`[String]`) — Поля контекста, необходимые механике.

  Поля каждого элемента `products` (`RecommendedProduct`):

  - `id` (`Int64`) — Идентификатор торгового предложения в RetailCRM.
  - `productID` (`Int64`) — Идентификатор товара в RetailCRM.
  - `name` (`String`) — Название предложения; если оно пустое — название товара.
  - `price` (`Double`) — Текущая цена предложения.
  - `oldPrice` (`Double`) — Предыдущая цена; при отсутствии — `0`.
  - `currency` (`String`) — Валюта цены.
  - `imageUrl` (`String`) — URL изображения предложения; если оно отсутствует — изображения товара. При отсутствии обоих — пустая строка.
  - `url` (`String`) — URL товара; при отсутствии — пустая строка.
  - `available` (`Bool`) — Признак доступности, возвращённый сервером; при отсутствии — `true`.

  Если сервер не передал `productIds`, `products` или `context.required`, SDK возвращает для них пустые массивы. Пустая подборка считается успешным результатом.

- `trackImpression(_:screenURI:title:)` и вариант с `completion` — записывают показ блока рекомендаций в очередь и возвращают ID события. `screenURI` должен быть абсолютным URI со схемой.
- `trackClick(_:productID:position:element:leaving:)` и вариант с `completion` — записывают нажатие на карточку в очередь и возвращают ID события. `productID` — ID товара из карточки; `position` — необязательный индекс с нуля.
- `onEventUpdate: ((TrackerEventUpdate) -> Void)?` — сообщает ID событий при постановке в очередь, отправке, доставке, повторной попытке, отклонении и удалении. Использует общий обработчик `Tracker`; назначение через один модуль заменяет обработчик другого. Может вызываться вне главного потока.

Успешный результат `trackImpression` или `trackClick` подтверждает запись события в очередь, но не доставку сервером.
Методы `trackImpression` и `trackClick` используют общий стартовый буфер и очередь `Tracker`.
Ждать завершения запуска перед их вызовом не требуется.

## Публичные ошибки

Публичные ошибки реализуют `LocalizedError`.
Сообщения фиксированных состояний доступны на русском, английском и испанском языках.
Диагностические подробности и сообщения сервера могут быть на языке источника.

Публичная ошибка модуля `Recommendations` - `RecommendationsError`

Операции `Recommendations` возвращают этот тип ошибки через `throw` или `completion`.
Общий обработчик `onReadyUpdate` передаёт `TrackerError`; см. [«Публичные ошибки трекера»](./tracker.md#публичные-ошибки).

- `invalidRequest(String)` — некорректные параметры запроса или события.
- `missingConnection` — отсутствуют данные подключённой сессии.
- `httpStatus(Int, [String])` — HTTP-статус и сообщения backend из `errors`.
- `invalidResponse(String)`, `requestFailed(String)` — ошибка ответа или запроса.
- `trackingUnavailable`, `consentRequired`, `trackingFailed(String)` — событие не принято трекером.
- `cancelled` — операция отменена.

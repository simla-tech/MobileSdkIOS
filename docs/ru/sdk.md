# RetailCRM iOS SDK

SDK позволяет подключить к iOS-приложению онлайн-консультант, трекинг действий клиентов,
товарные рекомендации и push-уведомления.

## Оглавление

- [Модули](#модули)
- [Требования](#требования)
- [Подключение](#подключение)
    - [SPM](#swift-package-manager)
    - [Cocoa Pods](#cocoapods)
- [Инициализация](#инициализация)
- [Наблюдение за HTTP-запросами](#наблюдение-за-http-запросами)
- [Идентификация клиента](#идентификация-клиента)
- [Использование модулей](#использование-модулей)
- [Публичные ошибки](#публичные-ошибки)
- [Локальное хранение](#локальное-хранение)
- [Проверка проекта](#проверка-проекта)
- [Участие в разработке](#участие-в-разработке)
- [Безопасность](#безопасность)
- [Лицензия](#лицензия)

## Модули

Swift-модуль / CocoaPods - Назначение

`Core` / `SimlaCore` - Общая runtime и точка входа `CrmSdk`
`OnlineConsultant` / `SimlaOnlineConsultant` - Онлайн-консультант 
`Tracker` / `SimlaTracker` - Трекинг действий клиентов 
`Recommendations` / `SimlaRecommendations` - Товарные рекомендации 
`PushService` / `SimlaPushService` - Firebase push-уведомления, при управлении Firebase и делегатами со стороны приложения
`PushNotificationExtension` / `SimlaPushNotificationExtension` - Обработка уведомлений в Notification Service Extension 

Модули используют общую сессию `Core`.
`Recommendations` использует общий `Tracker`.
`PushNotificationExtension` не зависит от `Core` и работает в процессе расширения приложения.

## Требования

- iOS 15 и выше.
- Для использования онлайн-консультанта в RetailCRM должен быть подключён модуль
  «Онлайн-консультант».
- Для рекомендаций нужна настроенная механика рекомендаций в RetailCRM.
- Для Firebase push-уведомлений нужны настройки Firebase и APNs в приложении.

## Подключение

### Swift Package Manager

В Xcode выберите **File → Add Package Dependencies** и укажите:

```text
https://github.com/simla-tech/MobileSdkIosTest.git
```

Выберите **Branch → main**. Для подключения по версии нужен опубликованный Git-тег. 

Добавьте продукт `Core` и необходимые продукты SDK к таргету приложения.
Например, для чата — `Core` и `OnlineConsultant`.
Зависимости выбранных продуктов SPM подключает автоматически.
Продукт `PushNotificationExtension` добавьте к таргету Notification Service Extension.

### CocoaPods

Добавьте общие настройки в `Podfile`:

```ruby
source 'https://cdn.cocoapods.org/'
platform :ios, '15.0'
use_frameworks! :linkage => :static

sdk_source = {
  :git => 'git@github.com:simla-tech/MobileSdkIosTest.git',
  :branch => 'main'
}
```

Выберите нужный вариант `target` ниже. Каждый пример включает все зависимости SDK необходимые дляработы того или иного модуля.
Если используете несколько модулей, объедините их списки в одном `target`, указав каждый pod один раз.

#### Онлайн-консультант

```ruby
target 'YourApp' do
  pod 'SimlaSDKConfiguration', sdk_source
  pod 'SimlaSQLiteStorage', sdk_source
  pod 'SimlaCore', sdk_source
  pod 'SimlaOnlineConsultant', sdk_source
end
```

#### Трекер

```ruby
target 'YourApp' do
  pod 'SimlaSDKConfiguration', sdk_source
  pod 'SimlaSQLiteStorage', sdk_source
  pod 'SimlaCore', sdk_source
  pod 'SimlaTracker', sdk_source
end
```

#### Товарные рекомендации

```ruby
target 'YourApp' do
  pod 'SimlaSDKConfiguration', sdk_source
  pod 'SimlaSQLiteStorage', sdk_source
  pod 'SimlaCore', sdk_source
  pod 'SimlaTracker', sdk_source
  pod 'SimlaRecommendations', sdk_source
end
```

#### Push-уведомления в приложении

```ruby
target 'YourApp' do
  pod 'SimlaSDKConfiguration', sdk_source
  pod 'SimlaSQLiteStorage', sdk_source
  pod 'SimlaCore', sdk_source
  pod 'SimlaPushNotificationExtension', sdk_source
  pod 'SimlaPushService', sdk_source
end
```

#### Notification Service Extension

```ruby
target 'YourAppNotificationExtension' do
  pod 'SimlaSDKConfiguration', sdk_source
  pod 'SimlaSQLiteStorage', sdk_source
  pod 'SimlaPushNotificationExtension', sdk_source
end
```

Замените имена таргетов на имена из проекта, выполните `pod install` и откройте созданный
`.xcworkspace`. Блок расширения нужен только при наличии Notification Service Extension.

При прямом Git-подключении внутренние модули `SimlaSDKConfiguration` и `SimlaSQLiteStorage` тоже перечисляются с `sdk_source`.
Firebase-зависимости CocoaPods получает из публичного каталога.

## Инициализация

Вызовите `CrmSdk.initialize` один раз при запуске приложения. Сразу после вызова настройте необходимые модули.
Инициализация и доступ к `CrmSdk.shared` выполняются на главном акторе.
`completion` сообщает результат подключения общей сессии.

Пример для UIKit:

```swift
import Core
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        CrmSdk.initialize(
            config: CrmSdkConfig(siteToken: "<site-token>"),
            customerIdentity: CrmSdkCustomerIdentity(
                customerId: 123,
                siteCustomerId: "customer-123",
                siteCode: "main"
            ),
            pageContext: ConnectPageContext(
                title: "Главная",
                url: URL(string: "https://example.com"),
                referURL: URL(string: "https://example.com")
            )
        ) { result in
            switch result {
            case .success:
                print("CrmSdk initialize success")
            case .failure(let error):
                print("CrmSdk initialize failure, error:\n\(error.localizedDescription)")
            }
        }
        self.configureOnlineConsultantChat()
        self.configurePush()
        self.configureTracker()
        self.configureRecommendations()
        return true
    }
}
```

- `config` — обязательные настройки SDK. `site-token` — токен сайта из настроек онлайн-консультанта или трекера RetailCRM.
- `customerIdentity` — необязательный идентификатор клиента в retailCRM. Укажите `customerId` или `siteCustomerId`; при использовании `siteCustomerId` также нужен `siteCode`.
- `pageContext` — сведения об экране при первоначальном подключении. `title` передаётся как `page_title`, `url` используется для фильтрации событий трекера, `referURL` передаётся как `refer_url`. Все поля необязательны.
- `completion` — обязательный обработчик `Result<Void, CoreError>` для первоначального подключения в варианте с обратным вызовом.

Кроме `siteToken`, `CrmSdkConfig` принимает необязательные параметры:

- `baseURL` — адрес сервера HTTP(S), по умолчанию `https://c.retailcrm.tech`. Можно указать домен или полный путь `/api/client/v1`; завершающие `/` удаляются. Адрес не должен содержать query или fragment. Используется всеми сетевыми модулями; WebSocket получает схему `ws` или `wss`.
- `requestTimeout` — таймаут ожидания данных в HTTP-запросе, в секундах. По умолчанию `30`.
- `resourceTimeout` — максимальная длительность HTTP-запроса, в секундах. По умолчанию `60`.
- `consultantConfig` — настройки чата. По умолчанию создаются автоматически.
- `trackerConfig` — настройки трекера. По умолчанию создаются автоматически.
- `networkObserver` — необязательный наблюдатель HTTP-запросов. По умолчанию — `nil`.

`CrmSdk.initialize(config:customerIdentity:pageContext:) async throws -> CrmSdk` возвращает экземпляр после успешного подключения. Вариант с `completion` возвращает экземпляр сразу, а результат подключения сообщает позже.

SDK запускает подключение к серверу после инициализации. Все подключённые модули используют общий экземпляр `CrmSdk`.
Модули SDK в приложении используют общую `URLSession`. `PushNotificationExtension` использует собственную сессию.

## Наблюдение за HTTP-запросами

Передайте `CrmSdkNetworkObserver` в `CrmSdkConfig.networkObserver` до инициализации для получения событий HTTP-запросов всех модулей SDK в приложении, включая `/connect` и загрузку ресурсов. По умолчанию — `nil`.

```swift
import Core
import Foundation

final class NetworkObserver: CrmSdkNetworkObserver {
    var collectsMetrics: Bool { true }

    func requestDidStart(_ event: CrmSdkNetworkRequest) {
        print(event.id, event.request, event.startedAt)
    }

    func requestDidComplete(_ event: CrmSdkNetworkResponse) {
        print(event.id, event.response as Any, event.responseBody as Any,
              event.error as Any, event.duration)
    }

    func requestDidCollectMetrics(_ metrics: URLSessionTaskMetrics, requestID: UUID) {
        print(requestID, metrics)
    }
}

let config = CrmSdkConfig(siteToken: "<site-token>", networkObserver: NetworkObserver())
```

Обработчики вызываются асинхронно на отдельной последовательной очереди. Начало предшествует завершению каждого запроса; каждая повторная попытка получает новый UUID. `startedAt` — время создания задачи; `duration` измеряется монотонными часами. Завершение описывает сетевой результат до проверки HTTP-статуса и декодирования: HTTP 4xx/5xx сами по себе не заполняют `error`, таймауты и отмена заполняют. `responseBody` содержит байты ответа data-задачи; при скачивании файла передаётся `nil` без чтения файла в память.

Метрики по умолчанию выключены. Для получения системных метрик задайте `collectsMetrics = true` и реализуйте `requestDidCollectMetrics`; запрос определяется по UUID. Метрики могут поступить до или после завершения. Сообщения WebSocket и ошибки декодирования в этот HTTP-интерфейс не входят.

SDK удерживает наблюдателя и передаёт события без сохранения истории запросов. Заголовки и тела передаются в исходном виде; маскирование и хранение определяет наблюдатель. Работа обработчика не задерживает завершение запроса. Наблюдатель должен поддерживать доступ из разных потоков, а обработчики — быстро завершаться.

`PushNotificationExtension` работает в отдельном процессе. Передайте наблюдателя отдельно через `PushNotificationHandler(siteToken:baseURL:networkObserver:)`; его публичные типы доступны через `import PushNotificationExtension`.

## Идентификация клиента

Если клиент известен при запуске, передайте `customerIdentity` в `CrmSdk.initialize`.
После входа или смены аккаунта вызовите `CrmSdk.shared.setCustomerIdentity(_:) async throws` или вариант с `completion`.
Метод обновляет идентификатор клиента и переподключает общую сессию SDK, чтобы подключенные модули, работали с текущим клиентом.
Дождитесь его успешного завершения перед дальнейшей работой с текущим клиентом.

```swift
import Core

@MainActor
func identifyCustomer() async throws {
    try await CrmSdk.shared.setCustomerIdentity(
        CrmSdkCustomerIdentity(
        // Внутренний ID клиента RetailCRM.
            customerId: 37
        )
    )
    
    try await CrmSdk.shared.setCustomerIdentity(
        CrmSdkCustomerIdentity(
        // ID клиента на стороне сайта и код сайта RetailCRM.
        // siteCustomerId и siteCode передаются только вместе.
            siteCustomerId: "customer-42",
            siteCode: "main"
        )
    )
    
    try await CrmSdk.shared.setCustomerIdentity(
        CrmSdkCustomerIdentity(
        // Оба способа идентификации.
        // Если модулю достаточно одного идентификатора,
        // SDK использует customerId в первую очередь.
            customerId: 37,
            siteCustomerId: "customer-42",
            siteCode: "main"
        )
    )
}
```

При выходе из аккаунта передайте `nil`:

```swift
@MainActor
func signOutFromSdk() async throws {
    try await CrmSdk.shared.setCustomerIdentity(nil)
}
```

Для привязки чата к клиенту CRM передайте `siteCustomerId` и `siteCode`. 
Одного внутреннего `customerId` для привязки чата недостаточно; его можно передавать дополнительно для остальных модулей.

Токены хранятся отдельно для каждой комбинации `siteToken` и `customerIdentity`.
В ключ хранения входят `siteCode`, `siteCustomerId` и, если задан, `customerId`.
Анонимный токен хранится отдельно для каждого `siteToken`.
При подключении используется только токен текущей identity, если его нет, `/connect` отправляется без `user.token`.
Анонимный токен не переносится в авторизованную сессию.
Гостевая история автоматически не переносится при входе, возврат к прежней identity использует её сохранённый токен.

## Использование модулей

После успешной инициализации экземпляр SDK доступен через `CrmSdk.shared`.
Свойства `onlineConsultant`, `tracker`, `recommendations`, `pushService`
создают соответствующий модуль при первом обращении и возвращают тот же экземпляр повторно.
Для доступа к API импортируйте нужный Swift-модуль.

Подробнее о модулях:

- [Онлайн-консультант](./onlineConsultant.md) — отображение чата.
- [Трекер](./tracker.md) — отправка событий.
- [Товарные рекомендации](./recommendations.md) — получение рекомендованных товаров и учёт
  взаимодействий.
- [Push-уведомления](./push-firebase.md) — настройка Firebase и регистрация категорий.

## Публичные ошибки

Публичные ошибки реализуют `LocalizedError`.
Сообщения фиксированных состояний доступны на русском, английском и испанском языках.
Диагностические подробности и сообщения сервера могут быть на языке источника.

Публичная ошибка модуля `Core` - `CoreError`

`CrmSdk.initialize` и `CrmSdk.shared.setCustomerIdentity` передают этот тип в `completion`.

Публичные `Codable`-модели `Core` преобразуют ошибки кодирования и декодирования в `CoreError`.

- `invalidCustomerIdentity(String)` — некорректный идентификатор клиента; строка содержит причину.
- `missingConnectionCredentials` — в ответе подключения нет данных сессии.
- `httpStatus(Int, [String])` — HTTP-статус и сообщения сервера.
- `keychainInvalidTokenData`, `keychainUnexpectedStatus(Int32)` — некорректный сохранённый токен или код ошибки Keychain.
- `requestEncodingFailed(String)`, `responseDecodingFailed(String)` — ошибка кодирования или декодирования.
- `requestFailed(String)`, `cancelled` — сбой запроса или отмена операции.
- `unexpected(String)` — непредвиденная ошибка операции.

## Локальное хранение

`SQLiteStorage` — внутренний модуль SQLite без зависимости от `Core`.
`SDKConfiguration` содержит общие адреса API для `Core` и `PushNotificationExtension`.

В Application Support используются отдельные базы:

- `crm_consultant_tracker.sqlite` — события Tracker;
- `crm_push_registration.sqlite` — отпечаток регистрации и списки категорий PushService;
- `crm_push_status_retries.sqlite` — очередь повторной отправки статусов push.

Метаданные файлового кэша OnlineConsultant хранятся в
`Library/Caches/ConsultantSDK/crm_consultant_cache.sqlite`, вложения — в соседнем каталоге `files`.
При открытии кэша удаляются записи без файлов и файлы без записей.
Ошибки удаления файлов при очистке возвращаются вызывающему коду.

Приложение и расширение хранят очереди в собственных контейнерах; App Group не требуется.
`PushServiceError.storage(String)` сообщает об ошибке доступа к базе регистрации push.

## Проверка проекта

В [GitHub Actions](../../.github/workflows/ci.yml) параллельно выполняются `SPM build` и
`Pod build`. `Pod build` устанавливает все локальные pod и собирает временное приложение
с Notification Service Extension. После успешных сборок запускаются семь заданий тестирования
модулей и SQLite-хранилища.
Push-тесты, требующие приложения-хоста, при текущем запуске SPM пропускаются.

## Участие в разработке

Перед созданием pull request:

1. Опишите проблему или предлагаемое изменение.
2. Добавьте тесты для изменённого поведения и запустите их в iOS Simulator.
3. Проверьте сборку SDK и подключение затронутых модулей в приложении.
4. При изменении публичного API обновите документацию и примеры.

## Безопасность

Не публикуйте сведения об уязвимостях в открытых issue.

Используйте GitHub Private Vulnerability Reporting: Security → Report a vulnerability. Если форма недоступна, сначала свяжитесь с сопровождающими проекта по непубличному каналу.

## Лицензия

Проект распространяется по лицензии Apache License 2.0. См. [LICENSE](../../LICENSE).

# Push-уведомления через Firebase

Модуль `push-firebase` подключает push-уведомления RetailCRM через Firebase Cloud Messaging:
регистрацию устройства, отображение уведомлений и отправку статусов.

## Оглавление

- [Доступ RetailCRM к отправке уведомлений](#доступ-retailcrm-к-отправке-уведомлений)
- [Подключение](#подключение)
- [Идентификация клиента](#идентификация-клиента)
- [Передача токена устройства](#передача-токена-устройства)
- [Регистрация push-токена и категорий](#регистрация-push-токена-и-категорий)
- [Обработка уведомлений](#обработка-уведомлений)
- [Обработка уведомлений при свёрнутом или закрытом приложении](#обработка-уведомлений-при-свёрнутом-или-закрытом-приложении)
- [Переходы и данные уведомления](#переходы-и-данные-уведомления)
- [Публичные методы и свойства](#публичные-методы-и-свойства)
- [Аналитика push-уведомлений](#аналитика-push-уведомлений)
- [Публичные ошибки](#публичные-ошибки)
- [Пример реализации AppDelegate](#пример-реализации-appdelegate)

## Доступ RetailCRM к отправке уведомлений

Чтобы RetailCRM мог отправлять уведомления через ваш Firebase-проект, предоставьте сервисному
аккаунту RetailCRM доступ к Firebase Cloud Messaging API.
Firebase [поддерживает](https://firebase.google.com/docs/cloud-messaging/send/v1-api#authorize_a_service_account_from_a_different_project)
отправку сообщений
сервисным аккаунтом из другого проекта.

1. Откройте [Google Cloud Console](https://console.cloud.google.com/) и выберите проект, к которому подключено ваше iOS-приложение.

2. Перейдите в **IAM & Admin → IAM** и нажмите **Grant access**.

3. В поле **New principals** укажите сервисный аккаунт RetailCRM:

   ```text
   firebase-adminsdk-fbsvc@push-service-sender.iam.gserviceaccount.com
   ```

4. Назначьте роль **Firebase Cloud Messaging API Admin** (`roles/firebasecloudmessaging.admin`).

5. Нажмите **Save**.

Эта роль предоставляет право отправлять сообщения через FCM API вашего
проекта. [Описание роли в документации Firebase](https://firebase.google.com/docs/projects/iam/roles-predefined-product#cloud-messaging-roles).

## Подключение

Настройте Firebase в приложении по [инструкции Firebase](https://firebase.google.com/docs/ios/setup).
Вызывайте `configurePush()` сразу после `CrmSdk.initialize(...)`. Регистрация ожидает готовности сессии и токена.

```swift

import Core
import PushService

CrmSdk.initialize(
    config: CrmSdkConfig(
        siteToken: "<site-token>"
    )
) { result in
    if case .failure(let error) = result {
        print(error.localizedDescription)
    }
}
configurePush()

private func configurePush() {
    let pushService = CrmSdk.shared.pushService
    pushService.onPushRegistrationResult = { result in
        switch result {
        case .success(let token):
            print("Push registration succeeded; token: \(token)")
        case .failure(let error):
            print("Push registration failed: \(error.localizedDescription)")
        }
    }
}
```

Настройка Firebase, получение FCM-токена или Firebase Installation ID, регистрация в APNs и назначение делегатов уведомлений выполняются в приложении.

Firebase должен быть настроен до появления всех условий для применения подписки.
Для регистрации токена, SDK получает идентификатор Firebase-проекта из `FirebaseApp.app()?.options.projectID`.

## Идентификация клиента

Сообщайте SDK о входе, смене аккаунта и выходе клиента через `CrmSdk.shared.setCustomerIdentity(...)`.
Подробнее — в разделе [«Идентификация клиента»](./sdk.md#идентификация-клиента).

## Передача токена устройства

Передайте токен устройства через `setToken(_:)`. Для FCM назначьте `Messaging.messaging().delegate = self`
в `AppDelegate` после настройки Firebase и вызова `CrmSdk.initialize`.
Используйте соответствующий вариант получения токена:

```swift
import UIKit
import Core
import PushService
import FirebaseMessaging
import FirebaseInstallations

// При использовании FCM
extension AppDelegate: MessagingDelegate {
    nonisolated func messaging(
        _ messaging: Messaging,
        didReceiveRegistrationToken fcmToken: String?
    ) {
        guard let fcmToken, !fcmToken.isEmpty else { return }
        Task { @MainActor in
            CrmSdk.shared.pushService.setToken(.fcm(fcmToken))
        }
    }
}

// При использовании FID
extension AppDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken

        Messaging.messaging().register { error in
            guard error == nil else {
                // Обработайте ошибку регистрации.
                return
            }

            Installations.installations().installationID { installationId, error in
                guard error == nil, let installationId else {
                    // Обработайте ошибку получения FID.
                    return
                }
                Task { @MainActor in
                    CrmSdk.shared.pushService.setToken(.fid(installationId))
                }
            }
        }
    }
}
```

Вместо вызова `pushService.setToken()` можно вызвать метод `pushService.setDeviceToken(_:completion:)`, чтобы SDK получил FCM-токен или Firebase Installation ID через Firebase.
Метод присваивает `Messaging.messaging().apnsToken = deviceToken`.
Если включён Firebase Installation ID, SDK вызывает `Messaging.messaging().register(...)` и получает FID через `Installations.installations().installationID(...)`, иначе запрашивает FCM-токен через `Messaging.messaging().token(...)`.

```swift
func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
    CrmSdk.shared.pushService.setDeviceToken(deviceToken) { result in
        switch result {
        case .success(let token):
            print("Токен: \(token)")
        case .failure(let error):
            print("Не удалось получить токен: \(error)")
        }
    }
}
```

Разница между методами:
- setToken сохраняет переданное значение в памяти и запускает применение подписки, когда готовы категории и сессия.
- setDeviceToken дополнительно передаёт APNs-токен в Firebase и получает FCM-токен либо FID, который затем использует для регистрации.
При использовании только setToken приложение самостоятельно отвечает за настройку Firebase, регистрацию в APNs и связь APNs-токена с Firebase.
Для FID также нужно самостоятельно выполнить регистрацию Firebase Messaging, которую SDK вызывает в setDeviceToken.

## Регистрация push-токена и категорий

Для регистрации push-токена и категорий CRM уведомлений используйте метод `registerNotificationCategories(_:completion:)`.

Метод выполняет следующие действия:
1. Удаляет дубли и сортирует коды: ["news", "sale", "news"] превращается в ["news", "sale"].
2. Сразу сохраняет желаемый список в памяти и UserDefaults. Подтверждённый список и отпечаток параметров сохраняются в `UserDefaults` после успешного ответа сервера, отдельно для каждого `siteToken`. Отпечаток учитывает токен, идентификаторы клиента, Firebase-проект и категории. При совпадении параметров запрос не повторяется, в том числе после перезапуска приложения. Проверка работает для регистрации и отписки; порядок категорий и дубли одинаковых кодов не влияют на сравнение.
3. Обновляет категории в UNUserNotificationCenter: создаёт категории с такими же идентификаторами, без кнопок и с .customDismissAction для обработки смахивания. Ранее управляемые SDK категории, отсутствующие в новом списке, удаляются. Другие категории приложения сохраняются, но при совпадении идентификатора категория будет заменена.
4. Ждёт валидный push-токен и подключённую сессию с идентификатором клиента, затем проверяет Firebase project ID.
5. Отправляет список категорий вместе с токеном и идентификаторами клиента на сервер. Если до начала запроса поступил другой список, прежний ожидающий вызов завершается с `PushServiceError.operationSuperseded`.

Приложение само хранит актуальный список категорий CRM уведомлений и передаёт его при каждом запуске и изменении подписки.
Для отключения передайте `[]`, для включения — нужные категории.
SDK применяет актуальный список категорий при изменении токена, категорий и состояния сессии.
До первого вызова `registerNotificationCategories` в текущем запуске автоматическая регистрация не выполняется.

При ошибке, переданный список и локальные категории сохраняются, подтверждённый список не изменяется.
Перед отправкой нового запроса старый отпечаток сбрасывается: если запрос завершился ошибкой, сервер мог успеть его обработать.
Повторов по таймеру нет: следующая попытка возможна при новом событии токена или сессии либо повторном вызове `registerNotificationCategories`.

На главном потоке назначьте обработчик результата, передайте актуальный список категорий и токен.
SDK выполнит регистрацию автоматически.
Метод сохраняет данные на backend Онлайн-консультанта.
Backend передаёт зарегистрированные токены и категории в RetailCRM фоновой задачей в начале каждого часа.
Поэтому подписка или отписка обычно начинает действовать после следующей успешной синхронизации — примерно в течение 60 минут после вызова метода.
При ошибках передачи задержка может быть больше.

```swift
import Foundation
import Core
import PushService

let pushService = CrmSdk.shared.pushService
pushService.onPushRegistrationResult = { result in
    if case let .failure(error) = result {
        print("Не удалось обновить push-подписку: \(error)")
    }
}
let availableCRMCategories = ["crm-category"]
pushService.registerNotificationCategories(availableCRMCategories) { result in
    if case let .failure(error) = result, error != .operationSuperseded {
        print("Не удалось применить категории уведомлений: \(error)")
    }
}
```

## Обработка уведомлений

Для обработки уведомлений необходимо реализовать методы делегата `UNUserNotificationCenterDelegate` и передать уведомления в сервис.
Если уведомление идентифицируется как уведомление из CRM, вызов системного `completionHandler` происходит на стороне SDK.

```swift
func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
) {
    if CrmSdk.shared.pushService.handleWillPresent(
        notification,
        withCompletionHandler: completionHandler,
        completion: { result in
            if case let .failure(error) = result { print(error) }
        }
    ) {
        // уведомление определено как CRM-уведомление и обработано сдк
        return
    }
    // Обработка других уведомлений приложением.
    completionHandler([.banner, .badge, .sound])
}

func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
) {
    if CrmSdk.shared.pushService.handleDidReceive(
        response,
        withCompletionHandler: completionHandler,
        completion: { result in
            if case let .failure(error) = result { print(error) }
        }
    ) {
        // уведомление определено как CRM-уведомление и обработано сдк
        return
    }
    // Обработка других уведомлений приложением.
    completionHandler()
}
```

Для тихих уведомлений включите Background Modes → Remote notifications.
Добавьте в `Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
<string>remote-notification</string>
</array>
```

```swift
func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
) {
    if CrmSdk.shared.pushService.handleSilentNotification(
        userInfo,
        fetchCompletionHandler: completionHandler,
        completion: { result in
            if case let .failure(error) = result { print(error) }
        }
    ) {
        return
    }

    // Обработка других уведомлений приложением.
    completionHandler(.noData)
}
```

## Обработка уведомлений при свёрнутом или закрытом приложении

iOS может доставить и показать обычное видимое push-уведомление без Notification Service Extension.
Чтобы SDK отправлял для него статус `.delivered` и добавлял кнопки или изображение до показа, добавьте **Notification Service Extension**.

В Xcode выберите **File → New → Target → Notification Service Extension**.
Добавьте продукт `PushNotificationExtension` к целевому модулю расширения и используйте `PushNotificationHandler` с теми же `siteToken` и `baseURL`, что и в приложении. Параметр `baseURL` необязателен, по умолчанию `https://c.retailcrm.tech`:

```swift
import UserNotifications
import PushNotificationExtension

final class NotificationService: UNNotificationServiceExtension {

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var originalContent: UNNotificationContent?
    private var bestAttemptContent: UNMutableNotificationContent?
    private var didComplete = false

    private let pushHandler = PushNotificationHandler(
        siteToken: "<siteToken>"
    )

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        DispatchQueue.main.async {
            self.contentHandler = contentHandler
            self.originalContent = request.content

            guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
                self.complete()
                return
            }

            self.bestAttemptContent = content
            if self.pushHandler.handle(request: request, content: content, completion: { [weak self] content in
                guard let self, !self.didComplete else { return }
                self.bestAttemptContent = content
                self.complete()
            }) {
                return
            }
            // Собственная обработка уведомлений других отправителей.
            self.complete()
        }
    }

    override func serviceExtensionTimeWillExpire() {
        complete()
    }

    private func complete() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.complete()
            }
            return
        }

        guard !didComplete else {
            return
        }

        didComplete = true
        let contentHandler = self.contentHandler
        self.contentHandler = nil
        if let bestAttemptContent {
            contentHandler?(bestAttemptContent)
        } else if let originalContent {
            contentHandler?(originalContent)
        }
    }
}
```

Необязательный параметр инициализатора `networkObserver` получает HTTP-события расширения независимо от наблюдателя приложения. См. [Наблюдение за HTTP-запросами](./sdk.md#наблюдение-за-http-запросами).

### Публичные методы `PushNotificationHandler`

- `init(siteToken: String)` — создаёт обработчик с тем же `siteToken`, что используется в приложении.
- `handle(request:content:completion:) -> Bool` — отправляет `.delivered`, добавляет кнопки и изображение. Помечает содержимое, чтобы приложение не отправляло статус повторно. Вызывает `completion` на главном потоке после завершения отправки статуса и обработки.

Для уведомлений других отправителей возвращает `false` без отправки статуса и вызова `completion`.
Завершайте системный `contentHandler` один раз в `completion` или в `serviceExtensionTimeWillExpire()`.

Модуль `PushNotificationExtension` не зависит от `Core`, Firebase и других модулей SDK.
Использует собственную `URLSession`: `30` секунд ожидания данных и `60` секунд на весь HTTP-запрос.

## Переходы и данные уведомления

Следующие поля настраиваются в RetailCRM при конфигурации push-уведомления и передаются SDK в userInfo уведомления:

| Поле           | Назначение                                                    |
|----------------|---------------------------------------------------------------|
| `click_action` | Адрес перехода или строковый идентификатор действия           |
| `ca_<ключ>`    | Дополнительные атрибуты для обработки уведомления приложением |
| `image_url`    | URL изображения, добавляемого к уведомлению                   |
| `buttons`      | JSON-массив до двух кнопок с полями `title` и `value`         |

Для отображения изображения и кнопок необходимо подключить Notification Service Extension с обработчиком SDK.

Поведение click_action:

"myapp://orders/123" — SDK передаёт строку в onNotificationOpen через NotificationAction.urlString. Приложение самостоятельно выполняет переход.
Поле отсутствует — SDK использует url или link, если они переданы. Если все три поля отсутствуют, NotificationAction.urlString равен nil, но обработчик открытия вызывается.

При нажатии на кнопку SDK передаёт её value в NotificationAction.urlString вместо значения click_action. При смахивании уведомления onNotificationOpen не вызывается.

Поля ca_* передаются приложению через NotificationAction.customAttributes. Префикс ca_ удаляется из ключа. Строковые значения сохраняются без изменений, числовые преобразуются в строки.

В текущей реализации customAttributes передаются только при наличии непустого click_action, url или link.

Например, для следующих пользовательских полей уведомления:

```json
{
    "click_action": "OPEN_ORDER",
    "ca_orderId": "123"
}
```

В приложении:

```swift
pushService.onNotificationOpen = { action in
    // Значение click_action или value нажатой кнопки.
    let actionValue = action.urlString // "OPEN_ORDER"
    // Поле ca_orderId передано с ключом orderId.
    let orderId = action.customAttributes?["orderId"] // "123"
    // Выполните переход на нужный экран приложения.
}
```

## Публичные методы и свойства

`CrmSdk.shared.pushService` возвращает `PushService`.

- `onStatusRetryUpdate: ((PushStatusRetryUpdate) -> Void)?` — сообщает вне главного потока о постановке push-статусов в очередь, начале повторных запросов, назначении следующей попытки, успехе и прекращении повторов. При назначении передаёт `pending` для уже ожидающих записей текущего сайта. Первоначальные запросы, не попавшие в очередь, не публикуются. Присвоение `nil` отключает подписку. События и их параметры описаны в разделе [«Аналитика push-уведомлений»](#аналитика-push-уведомлений).
- `onPushRegistrationResult: ((Result<PushToken, PushServiceError>) -> Void)?` — сообщает на главном потоке результат регистрации или отписки, включая ошибки проверки параметров. При назначении обработчика, пропуске уже подтверждённого состояния и замене ожидающего вызова через `operationSuperseded` событие не вызывается. Успех подтверждает принятие параметров сервером, но не доставку уведомлений.
- `registerNotificationCategories(_:)` принимает полный желаемый список кодов категорий CRM. Вызывайте метод при каждом запуске приложения и изменении подписки. Пустой список `[]` означает отписку от всех категорий. SDK ждёт валидный токен и подключённую сессию с идентификатором клиента; перед отправкой проверяет идентификатор Firebase-проекта. SDK регистрирует одноимённые категории iOS с `.customDismissAction` и удаляет ранее управляемые им категории, отсутствующие в новом списке. Остальные категории приложения сохраняются. Если код совпадает с категорией приложения, SDK заменит её вместе с действиями. Выбирайте непересекающиеся коды. Удаление категории iOS не блокирует доставку уведомлений и не меняет системное разрешение. Метод доступен как `async throws -> PushToken` и с `completion: (Result<PushToken, PushServiceError>) -> Void`. Результат возвращается после обновления локальных категорий и принятия параметров сервером, использования сохранённого подтверждения либо ошибки.
- `setToken(_ token: PushToken)` — принимает `.fcm(String)` или `.fid(String)`.
- `setDeviceToken(_:) async throws -> PushToken` и вариант с `completion` — принимает APNs-токен и получает через Firebase FCM-токен или Firebase Installation ID.
- `handleWillPresent(_:withCompletionHandler:completion:) -> Bool` — отправляет `.delivered` для уведомления в открытом приложении.
- `handleDidReceive(_:withCompletionHandler:completion:) -> Bool` — отправляет `.clicked` или `.swiped` при действии пользователя.
- `onNotificationOpen: ((NotificationAction) -> Void)?` — передаёт приложению исходную строку перехода (`urlString`). При нажатии на уведомление это ссылка перехода и дополнительные параметры если они заданы. При нажатии на кнопку это только ссылка перехода. SDK не открывает ссылку.
- `handleSilentNotification(_:fetchCompletionHandler:completion:) -> Bool` — отправляет `.delivered` для тихого уведомления RetailCRM.
- `PushService.version: String` — версия модуля.

Методы обработки уведомлений возвращают `true`, если уведомление распознано как RetailCRM.
В этом случае SDK вызывает переданный системный обработчик завершения сам.
При `false` приложение обрабатывает уведомление и вызывает обработчик самостоятельно.
Параметр `completion` получает `Result<Void, PushServiceError>` только для распознанных уведомлений.

## Аналитика push-уведомлений

SDK автоматически отправляет статусы взаимодействия с уведомлением:

| Событие                               | Статус      |
|---------------------------------------|-------------|
| Получение уведомления                 | `delivered` |
| Нажатие на уведомление или его кнопку | `clicked`   |
| Смахивание уведомления                | `swiped`    |

При сетевых ошибках, некорректном HTTP-ответе и HTTP `408`, `425`, `429`, `5xx` SDK сохраняет статус
для автоматического повтора. Всего выполняется до пяти попыток с задержками `10`, `20`, `40`, `80`
секунд; `Retry-After` может увеличить задержку. Исходные `changed_at` и `button_hash` сохраняются.
Остальные HTTP-ошибки и ошибки кодирования не повторяются.

Записи очереди сериализуются в JSON и сохраняются в `UserDefaults.standard` отдельно в приложении
и push-расширении. Повторы выполняются при доступной сети, пока соответствующий процесс работает;
после его остановки очередь возобновляется при создании
`PushService` или `PushNotificationHandler` в этом же процессе. iOS не гарантирует выполнение повторов
в приостановленном приложении или завершённом расширении.

`completion` вызывается один раз с результатом первой попытки, после сохранения временной ошибки
в очередь; последующие повторы не задерживают завершение обработки уведомления.

Для диагностики очереди назначьте `CrmSdk.shared.pushService.onStatusRetryUpdate`.
В расширении используется `PushNotificationHandler.onStatusRetryUpdate`:

```swift
CrmSdk.shared.pushService.onStatusRetryUpdate = { update in
    print("Push status retry:", update)
}
```

Обработчик получает `PushStatusRetryUpdate` вне главного потока. При назначении возвращаются события
`pending` для уже ожидающих записей текущего сайта, затем — новые изменения. Присвоение `nil` отключает
подписку. Обработчики разных экземпляров независимы; приложение и расширение наблюдают свои очереди.

| Событие | Значение |
|---------|----------|
| `pending` | Существующая запись, число начатых попыток и время следующей попытки |
| `queued` | Статус сохранён после первой временной ошибки; передаётся ошибка |
| `sending` | Начинается повторный запрос; номер включает первоначальную попытку |
| `retryScheduled` | Назначен повтор; передаются номер следующей попытки, время и ошибка |
| `delivered` | Сервер принял статус, в том числе при отдельной успешной отправке того же статуса |
| `rejected` | Повторы прекращены из-за окончательной ошибки |
| `dropped` | Исчерпано число попыток; последняя ошибка может отсутствовать после прерывания процесса |

Каждое событие содержит `PushStatusRetryEvent`: постоянный `id` записи, `pushID`, `status`, исходный
`changedAt` и `buttonHash`. `siteToken` не передаётся. Первоначальные запросы, не попавшие в очередь
повторов, через этот обработчик не публикуются. `delivered` означает принятие статуса сервером,
а не доставку самого уведомления устройству.

## Публичные ошибки

Публичные ошибки реализуют `LocalizedError`.
Сообщения фиксированных состояний доступны на русском, английском и испанском языках.
Диагностические подробности и сообщения сервера могут быть на языке источника.

Публичная ошибка модуля `PushService` - `PushServiceError`

Публичные операции `PushService` передают этот тип в `completion`. Отказ в разрешении на уведомления возвращается как `authorizationDenied`. Ошибки отправки статуса уведомления приходят как `statusReporting(...)` в обработчики уведомлений

- `invalidCustomerIdentity(String)`, `missingCustomerIdentifier` — некорректный или отсутствующий идентификатор клиента.
- `authorizationDenied` — пользователь отказал в разрешении на уведомления.
- `operationSuperseded` — ожидающий вызов заменён другим списком категорий до начала запроса.
- `emptyPushToken` — push-токен отсутствует; `registerNotificationCategories` ожидает его готовности перед отправкой.
- `emptyFCMToken`, `emptyFID`, `firebaseMessaging(Error)`, `firebaseInstallations(Error)`, `emptyFirebaseProjectID`, `firebaseInstallationIDDisabled` — ошибки получения токенов и настройки Firebase.
- `invalidHTTPResponse(String)`, `requestEncodingFailed(String)`, `requestFailed(String)`, `httpStatus(Int, [String])` — ошибки регистрации токена на сервере.
- `statusReporting(StatusReportingFailure)` — ошибка отправки статуса: `requestEncodingFailed(String)`, `invalidHTTPResponse(String)`, `requestFailed(String)` или `httpStatus(Int, [String])`.

## Пример реализации AppDelegate

В примере SDK запускается без идентификатора клиента. После входа клиента вызовите
`CrmSdk.shared.setCustomerIdentity(_:)` и дождитесь успешного завершения.
Передайте `customerId` либо `siteCustomerId` вместе с `siteCode`.
До получения идентификатора клиента регистрация push-подписки ожидает готовности сессии.
Подробнее — в разделе [«Идентификация клиента»](./sdk.md#идентификация-клиента).

```swift
import UIKit
import Core
import FirebaseCore
import PushService

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        self.configureServices(application)
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        CrmSdk.shared.pushService.setDeviceToken(deviceToken) { result in
            switch result {
            case .success(let token):
                print("Токен: \(token)")
            case .failure(let error):
                print("Не удалось получить токен: \(error)")
            }
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if CrmSdk.shared.pushService.handleSilentNotification(
            userInfo,
            fetchCompletionHandler: completionHandler,
            completion: { result in
                if case let .failure(error) = result { print(error) }
            }
        ) {
            return
        }
        // Обработка других уведомлений приложением.
        completionHandler(.noData)
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {}

    private func configureServices(_ application: UIApplication) {
        self.firebaseConfigure()
        self.registerNootificationCenter(application)
        self.configureCrmSdk()
    }

    private func firebaseConfigure() {
        FirebaseApp.configure()
    }

    private func registerNootificationCenter( _ application: UIApplication) {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("Ошибка запроса разрешения: \(error)")
            }
            print("Разрешение на уведомления: \(granted)")
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
    }

    private func configureCrmSdk() {
        CrmSdk.initialize(
            config: CrmSdkConfig(siteToken: Constants.consultantSiteToken)
//            customerIdentity: .init(customerId: nil, siteCustomerId: nil, siteCode: Constants.siteCode)
        ) { result in
            if case .failure(let error) = result {
                print("CrmSdk initialize failure, error:\n\(error.localizedDescription)")
            }
        }
        self.configurePush()
    }
}

// configure Push
private extension AppDelegate {

    private func configurePush() {
        let pushService = CrmSdk.shared.pushService
        pushService.onPushRegistrationResult = { result in
            switch result {
            case .success(let token):
                print("Push registration succeeded; token: \(token)")
            case .failure(let error):
                print("Push registration failed: \(error.localizedDescription)")
            }
        }
        pushService.onNotificationOpen = { action in
            let url = action.urlString
            let attributes = action.customAttributes
            // обработка нажатий
        }
        pushService.registerNotificationCategories(Constants.pushCategories) { result in
            if case let .failure(error) = result, error != .operationSuperseded {
                print("Could not apply push categories: \(error.localizedDescription)")
            }
        }
    }
}

// UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if CrmSdk.shared.pushService.handleWillPresent(
            notification,
            withCompletionHandler: completionHandler,
            completion: { result in
                if case let .failure(error) = result { print(error) }
            }
        ) {
            return
        }
        // Обработка других уведомлений приложением.
        completionHandler([.banner, .badge, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if CrmSdk.shared.pushService.handleDidReceive(
            response,
            withCompletionHandler: completionHandler,
            completion: { result in
                if case let .failure(error) = result { print(error) }
            }
        ) {
            return
        }
        // Обработка уведомления приложения.
        completionHandler()
    }
}

```

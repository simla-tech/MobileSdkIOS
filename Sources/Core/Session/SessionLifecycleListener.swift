/// Receives shared session lifecycle changes from `SessionRuntime`.
package protocol SessionLifecycleListener: AnyObject {
    func sessionDidConnect(
        credentials: SessionCredentials,
        pageContext: ConnectPageContext,
        user: ConnectUser,
        response: ConnectResponse,
        customerIdentity: CrmSdkCustomerIdentity?
    )
    func sessionDidDisconnect()
    func sessionDidFailToConnect(_ error: CoreError)
}

package extension SessionLifecycleListener {
    func sessionDidFailToConnect(_ error: CoreError) {}
}

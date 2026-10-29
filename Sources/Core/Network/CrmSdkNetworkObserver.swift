import SDKConfiguration

/// Receives SDK HTTP request, completion, and optional metrics events.
public typealias CrmSdkNetworkObserver = SDKConfiguration.CrmSdkNetworkObserver
/// A prepared HTTP request and its identifier and start time.
public typealias CrmSdkNetworkRequest = SDKConfiguration.CrmSdkNetworkRequest
/// The HTTP transport result, correlated with its request identifier.
public typealias CrmSdkNetworkResponse = SDKConfiguration.CrmSdkNetworkResponse

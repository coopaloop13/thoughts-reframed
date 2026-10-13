import Apollo
import ApolloAPI
import ApolloWebSocket
import Foundation

enum ApolloClientFactory {
    static func make(config: AppConfig, token: String?) -> ApolloClient {
        let store = ApolloStore()
        var headers: [String: String] = [:]
        if let token { headers["Authorization"] = "Bearer \(token)" }
        let http = RequestChainNetworkTransport(
            urlSession: URLSession.shared,
            interceptorProvider: DefaultInterceptorProvider.shared,
            store: store,
            endpointURL: config.httpURL,
            additionalHeaders: headers
        )
        let payload: JSONEncodableDictionary? = token.map { ["token": $0] }
        let ws = WebSocketTransport(urlSession: URLSession.shared, store: store, endpointURL: config.wsURL,
                                    configuration: .init(connectingPayload: payload))
        let split = SplitNetworkTransport(queryTransport: http, mutationTransport: http,
                                          subscriptionTransport: ws, uploadTransport: http)
        return ApolloClient(networkTransport: split, store: store)
    }
}

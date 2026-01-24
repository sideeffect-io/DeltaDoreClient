import Foundation

enum TydomRawMessageParser {
    static func parse(_ data: Data, httpParser: TydomHTTPParser = TydomHTTPParser()) -> TydomRawMessage {
        switch httpParser.parse(data) {
        case .success(let frame):
            return TydomRawMessage(
                payload: data,
                frame: frame,
                uriOrigin: frame.uriOrigin,
                transactionId: frame.transactionId,
                parseError: nil
            )
        case .failure(let error):
            return TydomRawMessage(
                payload: data,
                frame: nil,
                uriOrigin: nil,
                transactionId: nil,
                parseError: String(describing: error)
            )
        }
    }
}

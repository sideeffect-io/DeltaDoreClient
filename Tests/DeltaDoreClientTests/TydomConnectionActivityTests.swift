import Foundation
import Testing
@testable import DeltaDoreClient

@Test func connection_appActivityToggleUpdatesState() async {
    // Given
    let connection = TydomConnection(
        configuration: .init(
            mode: .local(host: "example.local"),
            mac: "AA:BB:CC:DD:EE:FF",
            password: "password"
        )
    )

    // When
    let initial = await connection.isAppActive()
    await connection.setAppActive(false)
    let updated = await connection.isAppActive()

    // Then
    #expect(initial == true)
    #expect(updated == false)
}

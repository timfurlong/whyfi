import CoreWLAN
import Foundation

/// Reads the Mac's Wi-Fi link with CoreWLAN.
final class WiFiMonitor: SignalSource, @unchecked Sendable {
    private let client = CWWiFiClient.shared()

    var interfaceName: String? { client.interface()?.interfaceName }

    func read(at time: Date) -> SignalReading? {
        guard let wifi = client.interface(), wifi.powerOn(), let channel = wifi.wlanChannel() else { return nil }
        let rssi = wifi.rssiValue()
        guard rssi != 0 else { return nil }
        return SignalReading(
            time: time, rssi: rssi, noise: wifi.noiseMeasurement(), txRate: wifi.transmitRate(),
            channel: channel.channelNumber, band: Self.band(channel.channelBand),
            widthMHz: Self.width(channel.channelWidth), bssid: wifi.bssid())
    }

    static func band(_ band: CWChannelBand) -> WiFiBand {
        switch band {
        case .band2GHz: .ghz2_4
        case .band5GHz: .ghz5
        case .band6GHz: .ghz6
        default: .unknown
        }
    }

    static func width(_ width: CWChannelWidth) -> Int {
        switch width {
        case .width20MHz: 20
        case .width40MHz: 40
        case .width80MHz: 80
        case .width160MHz: 160
        default: 0
        }
    }
}

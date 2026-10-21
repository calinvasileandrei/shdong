import Foundation
import IOKit
import IOKit.serial

/// Watches for serial ports that belong to a USB device with the given VID/PID and reports
/// their callout path (`/dev/cu.usbmodem…`). Callbacks run on the main queue.
final class DeviceWatcher {
    private let vendorID: Int
    private let productID: Int
    private var port: IONotificationPortRef?
    private var addedIter: io_iterator_t = 0
    private var removedIter: io_iterator_t = 0

    var onAppear: ((String) -> Void)?
    var onDisappear: ((String) -> Void)?

    init(vendorID: Int, productID: Int) {
        self.vendorID = vendorID
        self.productID = productID
    }

    deinit { stop() }

    func start() {
        guard port == nil else { return }
        let port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, .main)
        self.port = port
        let ctx = Unmanaged.passUnretained(self).toOpaque()

        IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, matching(), { ctx, iter in
            Unmanaged<DeviceWatcher>.fromOpaque(ctx!).takeUnretainedValue().drain(iter, added: true)
        }, ctx, &addedIter)
        drain(addedIter, added: true) // existing devices + arms the notification

        IOServiceAddMatchingNotification(port, kIOTerminatedNotification, matching(), { ctx, iter in
            Unmanaged<DeviceWatcher>.fromOpaque(ctx!).takeUnretainedValue().drain(iter, added: false)
        }, ctx, &removedIter)
        drain(removedIter, added: false)
    }

    func stop() {
        if addedIter != 0 { IOObjectRelease(addedIter); addedIter = 0 }
        if removedIter != 0 { IOObjectRelease(removedIter); removedIter = 0 }
        if let port { IONotificationPortDestroy(port) }
        port = nil
    }

    private func matching() -> CFDictionary {
        let dict = IOServiceMatching(kIOSerialBSDServiceValue) as NSMutableDictionary
        dict[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes
        return dict
    }

    private func drain(_ iter: io_iterator_t, added: Bool) {
        while case let service = IOIteratorNext(iter), service != 0 {
            defer { IOObjectRelease(service) }
            guard matchesUSB(service), let path = calloutPath(service) else { continue }
            added ? onAppear?(path) : onDisappear?(path)
        }
    }

    private func matchesUSB(_ service: io_object_t) -> Bool {
        func intProp(_ key: String) -> Int? {
            IORegistryEntrySearchCFProperty(service, kIOServicePlane, key as CFString, nil,
                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) as? Int
        }
        return intProp("idVendor") == vendorID && intProp("idProduct") == productID
    }

    private func calloutPath(_ service: io_object_t) -> String? {
        IORegistryEntryCreateCFProperty(service, kIOCalloutDeviceKey as CFString, nil, 0)?
            .takeRetainedValue() as? String
    }
}

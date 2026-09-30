import Foundation

let delegate = PreviewImageService()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()

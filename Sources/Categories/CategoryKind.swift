import SwiftUI

enum CategoryKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case photosAndVideos
    case messagesAndMail
    case leftoverAppData
    case iPhoneBackups
    case timeMachineSnapshots
    case forgottenLargeFiles
    case cachesAndLogs
    case trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photosAndVideos: 
            return "Photos & Videos"
        case .messagesAndMail:
            return "Messages & Mail"
        case .leftoverAppData:
            return "Leftover App Data"
        case .iPhoneBackups:
            return "Old iPhone Backups"
        case .timeMachineSnapshots:
            return "Time Machine Snapshots"
        case .forgottenLargeFiles:
            return "Forgotten Large Files"
        case .cachesAndLogs:
            return "Caches & Logs"
        case .trash:
            return "Trash"
        }
    }

    var explanation: String {
        switch self {
        case .photosAndVideos:
            "Your Photos library and Movies folder."
        case .messagesAndMail:
            "Attachments cached from Messages and Mail."
        case .leftoverAppData:
            "Support files left behind by deleted apps."
        case .iPhoneBackups:
            "Local backups of your iPhone or iPad."
        case .timeMachineSnapshots:
            "Local Time Machine snapshots, hidden from Finder."
        case .forgottenLargeFiles:
            "Large files untouched for 6+ months."
        case .cachesAndLogs:
            "Background caches and logs."
        case .trash:
            "Staged for deletion."
        }
    }

    var lowercasedNoun: String {
        switch self {
        case .photosAndVideos: 
            return "photos or videos"
        case .messagesAndMail:
            return "Messages or Mail attachments"
        case .leftoverAppData: 
            return "leftover app data"
        case .iPhoneBackups:
            return "iPhone backups"
        case .timeMachineSnapshots:
            return "Time Machine snapshots"
        case .forgottenLargeFiles:
            return "forgotten large files"
        case .cachesAndLogs:
            return "caches or logs"
        case .trash:
            return "trash"
        }
    }

    var systemImage: String {
        switch self {
        case .photosAndVideos: 
            return "photo.on.rectangle.angled"
        case .messagesAndMail:
            return "envelope.fill"
        case .leftoverAppData:
            return "app.dashed"
        case .iPhoneBackups:
            return "iphone"
        case .timeMachineSnapshots:
            return "clock.arrow.circlepath"
        case .forgottenLargeFiles:
            return "doc.zipper"
        case .cachesAndLogs:
            return "internaldrive"
        case .trash:
            return "trash.fill"
        }
    }

    var hue: Double {
        switch self {
        case .photosAndVideos:
            return 330 / 360
        case .messagesAndMail:
            return 210 / 360
        case .leftoverAppData:
            return 30 / 360
        case .iPhoneBackups:
            return 180 / 360
        case .timeMachineSnapshots:
            return 260 / 360
        case .forgottenLargeFiles:
            return 45 / 360
        case .cachesAndLogs:
            return 140 / 360
        case .trash:
            return 5 / 360
        }
    }

    var tintColor: Color {
        switch self {
        case .photosAndVideos:
            return Color(hue: hue, saturation: 0.66, brightness: 0.86)
        case .messagesAndMail:
            return Color(hue: hue, saturation: 0.66, brightness: 0.86)
        case .leftoverAppData:
            return Color(hue: hue, saturation: 0.66, brightness: 0.86)
        case .iPhoneBackups:
            return Color(hue: hue, saturation: 0.62, brightness: 0.8)
        case .timeMachineSnapshots:
            return Color(hue: hue, saturation: 0.62, brightness: 0.84)
        case .forgottenLargeFiles:
            return Color(hue: hue, saturation: 0.66, brightness: 0.84)
        case .cachesAndLogs:
            return Color(hue: hue, saturation: 0.58, brightness: 0.78)
        case .trash:
            return Color(hue: hue, saturation: 0.66, brightness: 0.82)
        }
    }
}

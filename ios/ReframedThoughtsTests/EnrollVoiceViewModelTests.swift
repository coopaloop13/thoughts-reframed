import Testing
import Foundation
@testable import ReframedThoughts

@MainActor
struct EnrollVoiceViewModelTests {
    func recording(duration: TimeInterval, permission: AudioRecorder.Permission = .granted) -> Recording {
        Recording(requestPermission: { permission }, start: {}, stop: { URL(fileURLWithPath: "/tmp/v.m4a") }, duration: { duration })
    }

    @Test func permissionDeniedPhase() async {
        let vm = EnrollVoiceViewModel(api: .stub(), recorder: recording(duration: 0, permission: .denied))
        await vm.record()
        #expect(vm.phase == .permissionDenied)
    }
    @Test func tooShortRecordingIsRejected() async {
        let vm = EnrollVoiceViewModel(api: .stub(), recorder: recording(duration: 3))
        await vm.record(); vm.stop()
        #expect(vm.phase == .failed("Please read the whole paragraph (at least 8 seconds)."))
    }
    @Test func tooLongRecordingIsRejected() async {
        let vm = EnrollVoiceViewModel(api: .stub(), recorder: recording(duration: 21))
        await vm.record(); vm.stop()
        #expect(vm.phase == .failed("Please keep it under 20 seconds and read at a natural pace."))
    }
    @Test func autoStopSavesTakeForReview() async throws {
        let vm = EnrollVoiceViewModel(api: .stub(), recorder: recording(duration: 12), autoStopAfter: 0.05)
        await vm.record()
        #expect(vm.phase == .recording)
        try await Task.sleep(for: .milliseconds(300))
        guard case .review = vm.phase else { Issue.record("expected review, got \(vm.phase)"); return }
    }
    @Test func retakeCancelsAutoStop() async throws {
        let vm = EnrollVoiceViewModel(api: .stub(), recorder: recording(duration: 12), autoStopAfter: 0.05)
        await vm.record(); vm.stop(); vm.retake()
        try await Task.sleep(for: .milliseconds(300))
        #expect(vm.phase == .idle)
    }
    @Test func uploadsAndReportsUser() async {
        let uploaded = Captured<(URL, String)?>(nil)
        let api = API.stub(enrollVoice: { url, text in uploaded.value = (url, text); return User(id: "u", hasVoice: true) })
        let vm = EnrollVoiceViewModel(api: api, recorder: recording(duration: 12))
        await vm.record(); vm.stop()
        guard case .review = vm.phase else { Issue.record("expected review"); return }
        await vm.upload()
        #expect(vm.phase == .done(User(id: "u", hasVoice: true)))
        #expect(uploaded.value?.1 == EnrollVoiceViewModel.referenceText)
    }
    @Test func uploadFailureShowsMessage() async {
        let vm = EnrollVoiceViewModel(api: .stub(enrollVoice: { _, _ in throw APIError.server("Unexpected error.") }), recorder: recording(duration: 12))
        await vm.record(); vm.stop(); await vm.upload()
        #expect(vm.phase == .failed("Unexpected error."))
    }

    func tempFileRecording(duration: TimeInterval) throws -> (Recording, URL) {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
        try Data().write(to: url)
        return (Recording(requestPermission: { .granted }, start: {}, stop: { url }, duration: { duration }), url)
    }
    @Test func tooShortTakeDeletesFile() async throws {
        let (rec, url) = try tempFileRecording(duration: 3)
        let vm = EnrollVoiceViewModel(api: .stub(), recorder: rec)
        await vm.record(); vm.stop()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
    @Test func retakeDeletesFile() async throws {
        let (rec, url) = try tempFileRecording(duration: 12)
        let vm = EnrollVoiceViewModel(api: .stub(), recorder: rec)
        await vm.record(); vm.stop()
        #expect(FileManager.default.fileExists(atPath: url.path))
        vm.retake()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func uploadThenPreviewsVoice() async {
        let url = URL(string: "https://r2/preview.mp3")!
        let api = API.stub(enrollVoice: { _, _ in User(id: "u", hasVoice: true) }, previewVoice: { url })
        let vm = EnrollVoiceViewModel(api: api, recorder: recording(duration: 12))
        await vm.record(); vm.stop(); await vm.upload()
        #expect(vm.phase == .preview(url, User(id: "u", hasVoice: true)))
    }
    @Test func keepFromPreviewFinishes() async {
        let api = API.stub(enrollVoice: { _, _ in User(id: "u", hasVoice: true) }, previewVoice: { URL(string: "https://r2/p.mp3")! })
        let vm = EnrollVoiceViewModel(api: api, recorder: recording(duration: 12))
        await vm.record(); vm.stop(); await vm.upload(); vm.keep()
        #expect(vm.phase == .done(User(id: "u", hasVoice: true)))
    }
    @Test func retakeFromPreviewRestarts() async {
        let api = API.stub(enrollVoice: { _, _ in User(id: "u", hasVoice: true) }, previewVoice: { URL(string: "https://r2/p.mp3")! })
        let vm = EnrollVoiceViewModel(api: api, recorder: recording(duration: 12))
        await vm.record(); vm.stop(); await vm.upload(); vm.retake()
        #expect(vm.phase == .idle)
    }
    @Test func previewFailureStillCompletesEnrollment() async {
        let api = API.stub(enrollVoice: { _, _ in User(id: "u", hasVoice: true) }, previewVoice: { throw APIError.transport("down") })
        let vm = EnrollVoiceViewModel(api: api, recorder: recording(duration: 12))
        await vm.record(); vm.stop(); await vm.upload()
        #expect(vm.phase == .done(User(id: "u", hasVoice: true)))
    }
}

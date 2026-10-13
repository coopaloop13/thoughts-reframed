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
}

import IssueMonitoring

struct ChatAcceptanceIssueDiagnostics: Sendable {
    let publishFailing: IssueDiagnostic
    let unacknowledged: IssueDiagnostic
}

extension ChatAcceptanceIssueDiagnostics {
    static func make(reporter: IssueReporting) -> Self {
        guard IssueMonitoringFactory.isReportingSupported else {
            return Self(publishFailing: NoopIssueDiagnostic(), unacknowledged: NoopIssueDiagnostic())
        }

        let flow: StaticString = "chat-acceptance"

        return Self(
            publishFailing: ThresholdIssueDiagnostic(
                flow: flow,
                kind: "publish-failing",
                threshold: 3,
                reporter: reporter
            ),
            unacknowledged: ThresholdIssueDiagnostic(flow: flow, kind: "unacknowledged", reporter: reporter)
        )
    }
}

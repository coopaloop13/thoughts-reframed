// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension GQL {
  nonisolated struct SendTurnMutation: GraphQLMutation {
    static let operationName: String = "SendTurn"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"mutation SendTurn($sessionId: ID!, $recording: File!) { sendTurn(sessionId: $sessionId, recording: $recording) { __typename ...TurnFields } }"#,
        fragments: [TurnFields.self]
      ))

    public var sessionId: ID
    public var recording: File

    public init(
      sessionId: ID,
      recording: File
    ) {
      self.sessionId = sessionId
      self.recording = recording
    }

    @_spi(Unsafe) public var __variables: Variables? { [
      "sessionId": sessionId,
      "recording": recording
    ] }

    nonisolated struct Data: GQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { GQL.Objects.Mutation }
      static var __selections: [ApolloAPI.Selection] { [
        .field("sendTurn", SendTurn.self, arguments: [
          "sessionId": .variable("sessionId"),
          "recording": .variable("recording")
        ]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        SendTurnMutation.Data.self
      ] }

      var sendTurn: SendTurn { __data["sendTurn"] }

      /// SendTurn
      nonisolated struct SendTurn: GQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { GQL.Objects.Turn }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .fragment(TurnFields.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          SendTurnMutation.Data.SendTurn.self,
          TurnFields.self
        ] }

        var id: GQL.ID { __data["id"] }
        var status: GraphQLEnum<GQL.SessionStatus> { __data["status"] }
        var userText: String? { __data["userText"] }
        var agentText: String? { __data["agentText"] }
        var audioUrl: String? { __data["audioUrl"] }
        var crisis: Bool { __data["crisis"] }
        var closing: Bool { __data["closing"] }
        var error: String? { __data["error"] }
        var createdAt: GQL.DateTime { __data["createdAt"] }

        struct Fragments: FragmentContainer {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          var turnFields: TurnFields { _toFragment() }
        }
      }
    }
  }

}
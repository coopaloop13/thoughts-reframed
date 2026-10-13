// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension GQL {
  nonisolated struct CreateSessionMutation: GraphQLMutation {
    static let operationName: String = "CreateSession"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"mutation CreateSession($recording: File!) { createSession(recording: $recording) { __typename ...SessionFields } }"#,
        fragments: [SessionFields.self]
      ))

    public var recording: File

    public init(recording: File) {
      self.recording = recording
    }

    @_spi(Unsafe) public var __variables: Variables? { ["recording": recording] }

    nonisolated struct Data: GQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { GQL.Objects.Mutation }
      static var __selections: [ApolloAPI.Selection] { [
        .field("createSession", CreateSession.self, arguments: ["recording": .variable("recording")]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        CreateSessionMutation.Data.self
      ] }

      var createSession: CreateSession { __data["createSession"] }

      /// CreateSession
      nonisolated struct CreateSession: GQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { GQL.Objects.Session }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .fragment(SessionFields.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          CreateSessionMutation.Data.CreateSession.self,
          SessionFields.self
        ] }

        var id: GQL.ID { __data["id"] }
        var status: GraphQLEnum<GQL.SessionStatus> { __data["status"] }
        var transcript: String? { __data["transcript"] }
        var reframedText: String? { __data["reframedText"] }
        var audioUrl: String? { __data["audioUrl"] }
        var error: String? { __data["error"] }
        var createdAt: GQL.DateTime { __data["createdAt"] }

        struct Fragments: FragmentContainer {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          var sessionFields: SessionFields { _toFragment() }
        }
      }
    }
  }

}
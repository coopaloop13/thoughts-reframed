// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension GQL {
  nonisolated struct SessionUpdatedSubscription: GraphQLSubscription {
    static let operationName: String = "SessionUpdated"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"subscription SessionUpdated($id: ID!) { sessionUpdated(id: $id) { __typename ...SessionFields } }"#,
        fragments: [SessionFields.self, TurnFields.self]
      ))

    public var id: ID

    public init(id: ID) {
      self.id = id
    }

    @_spi(Unsafe) public var __variables: Variables? { ["id": id] }

    nonisolated struct Data: GQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { GQL.Objects.Subscription }
      static var __selections: [ApolloAPI.Selection] { [
        .field("sessionUpdated", SessionUpdated.self, arguments: ["id": .variable("id")]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        SessionUpdatedSubscription.Data.self
      ] }

      var sessionUpdated: SessionUpdated { __data["sessionUpdated"] }

      /// SessionUpdated
      nonisolated struct SessionUpdated: GQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { GQL.Objects.Session }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .fragment(SessionFields.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          SessionUpdatedSubscription.Data.SessionUpdated.self,
          SessionFields.self
        ] }

        var id: GQL.ID { __data["id"] }
        var status: GraphQLEnum<GQL.SessionStatus> { __data["status"] }
        var transcript: String? { __data["transcript"] }
        var reframedText: String? { __data["reframedText"] }
        var audioUrl: String? { __data["audioUrl"] }
        var error: String? { __data["error"] }
        var createdAt: GQL.DateTime { __data["createdAt"] }
        var crisis: Bool { __data["crisis"] }
        var turns: [Turn] { __data["turns"] }

        struct Fragments: FragmentContainer {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          var sessionFields: SessionFields { _toFragment() }
        }

        typealias Turn = SessionFields.Turn
      }
    }
  }

}
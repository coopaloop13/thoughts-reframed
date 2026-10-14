// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension GQL {
  nonisolated struct SessionsQuery: GraphQLQuery {
    static let operationName: String = "Sessions"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query Sessions($limit: Int, $before: DateTime) { sessions(limit: $limit, before: $before) { __typename ...SessionFields } }"#,
        fragments: [SessionFields.self, TurnFields.self]
      ))

    public var limit: GraphQLNullable<Int32>
    public var before: GraphQLNullable<DateTime>

    public init(
      limit: GraphQLNullable<Int32>,
      before: GraphQLNullable<DateTime>
    ) {
      self.limit = limit
      self.before = before
    }

    @_spi(Unsafe) public var __variables: Variables? { [
      "limit": limit,
      "before": before
    ] }

    nonisolated struct Data: GQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { GQL.Objects.Query }
      static var __selections: [ApolloAPI.Selection] { [
        .field("sessions", [Session].self, arguments: [
          "limit": .variable("limit"),
          "before": .variable("before")
        ]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        SessionsQuery.Data.self
      ] }

      var sessions: [Session] { __data["sessions"] }

      /// Session
      nonisolated struct Session: GQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { GQL.Objects.Session }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .fragment(SessionFields.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          SessionsQuery.Data.Session.self,
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
// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension GQL {
  nonisolated struct TurnUpdatedSubscription: GraphQLSubscription {
    static let operationName: String = "TurnUpdated"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"subscription TurnUpdated($id: ID!) { turnUpdated(id: $id) { __typename ...TurnFields } }"#,
        fragments: [TurnFields.self]
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
        .field("turnUpdated", TurnUpdated.self, arguments: ["id": .variable("id")]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        TurnUpdatedSubscription.Data.self
      ] }

      var turnUpdated: TurnUpdated { __data["turnUpdated"] }

      /// TurnUpdated
      nonisolated struct TurnUpdated: GQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { GQL.Objects.Turn }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .fragment(TurnFields.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          TurnUpdatedSubscription.Data.TurnUpdated.self,
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